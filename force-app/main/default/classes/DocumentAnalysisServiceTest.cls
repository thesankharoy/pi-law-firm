@isTest
private class DocumentAnalysisServiceTest {
    // ── Mock handling both the S3 presign (AWS_Lambda) and Anthropic callouts ──
    private class DualMock implements HttpCalloutMock {
        Integer anthropicStatus;
        String anthropicBody;
        DualMock(Integer status, String body) {
            this.anthropicStatus = status;
            this.anthropicBody = body;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('Anthropic')) {
                res.setStatusCode(anthropicStatus);
                res.setBody(anthropicBody);
            } else {
                // S3LambdaService presign call → return a presigned URL
                res.setStatusCode(200);
                res.setBody('{"url":"https://s3.example.com/presigned?sig=abc"}');
            }
            return res;
        }
    }

    private static String goodAnthropicBody() {
        // content[].text is the JSON fact object Claude is asked to return.
        String facts =
            '{\\"documentType\\":\\"Medical Record\\",' +
            '\\"summary\\":\\"Patient seen for lower back pain after an MVA.\\",' +
            '\\"keyDates\\":[{\\"label\\":\\"Date of service\\",\\"date\\":\\"2026-01-12\\"}],' +
            '\\"parties\\":[{\\"name\\":\\"Jane Roe\\",\\"role\\":\\"Patient\\"}],' +
            '\\"providers\\":[{\\"name\\":\\"Mercy Clinic\\",\\"type\\":\\"Hospital\\"}],' +
            '\\"injuries\\":[\\"Lumbar strain\\"],' +
            '\\"amounts\\":[{\\"label\\":\\"Total billed\\",\\"value\\":\\"$1,250.00\\"}],' +
            '\\"identifiers\\":[{\\"label\\":\\"MRN\\",\\"value\\":\\"884213\\"}],' +
            '\\"actionItems\\":[\\"Request full imaging report\\"]}';
        return '{"content":[{"type":"text","text":"' + facts + '"}],' +
            '"model":"claude-sonnet-4-6","usage":{"input_tokens":1200,"output_tokens":340}}';
    }

    @testSetup
    static void setup() {
        Intake__c i = new Intake__c();
        // Populate any required picklists dynamically so the test isn't tied to this
        // org's exact picklist values (Incident_Type__c is required here).
        i.Incident_Type__c = firstPicklistValue(Intake__c.Incident_Type__c);
        insert i;
        // MIME_Type__c is only 10 chars in this org; analyzability is driven by the
        // filename extension, so leave MIME null and let '.pdf' classify it.
        insert new Document__c(
            Name = 'medical-report.pdf',
            Intake__c = i.Id,
            S3_Key__c = 'Intake/' + i.Id + '/abc123.pdf',
            Status__c = 'Active'
        );
    }

    private static Id docId() {
        return [SELECT Id FROM Document__c LIMIT 1].Id;
    }

    private static String firstPicklistValue(Schema.SObjectField f) {
        List<Schema.PicklistEntry> entries = f.getDescribe().getPicklistValues();
        for (Schema.PicklistEntry e : entries) {
            if (e.isActive()) return e.getValue();
        }
        return entries.isEmpty() ? null : entries[0].getValue();
    }

    @isTest
    static void testAnalyzeFresh() {
        Test.setMock(HttpCalloutMock.class, new DualMock(200, goodAnthropicBody()));
        Test.startTest();
        DocumentAnalysisService.AnalysisDTO dto =
            DocumentAnalysisService.analyze(docId(), false);
        Test.stopTest();

        System.assertEquals('Completed', dto.status, 'should complete');
        System.assertEquals('Medical Record', dto.documentType);
        System.assert(dto.summary.contains('lower back pain'), 'summary stored');
        System.assertEquals(1200, dto.inputTokens);

        Document_Analysis__c rec = [
            SELECT Status__c, Summary__c, Extracted_JSON__c, Model__c, Analyzed_On__c
            FROM Document_Analysis__c
            WHERE Document__c = :docId()
        ];
        System.assertEquals('Completed', rec.Status__c);
        System.assert(rec.Extracted_JSON__c.contains('Lumbar strain'), 'json persisted');
        System.assertNotEquals(null, rec.Analyzed_On__c);
    }

    @isTest
    static void testCacheHitSkipsCallout() {
        // Pre-seed a completed analysis; analyze(false) must return it with NO callout.
        insert new Document_Analysis__c(
            Document__c = docId(),
            Status__c = 'Completed',
            Document_Type__c = 'Police Report',
            Summary__c = 'cached',
            Extracted_JSON__c = '{"summary":"cached"}',
            Analyzed_On__c = System.now()
        );
        Test.startTest();
        // No mock set: a callout here would throw, proving the cache short-circuits.
        DocumentAnalysisService.AnalysisDTO dto =
            DocumentAnalysisService.analyze(docId(), false);
        Test.stopTest();

        System.assertEquals('Police Report', dto.documentType, 'served from cache');
        System.assertEquals(1, [SELECT COUNT() FROM Document_Analysis__c], 'no new record');
    }

    @isTest
    static void testForceReanalyzeUpdatesSameRecord() {
        insert new Document_Analysis__c(
            Document__c = docId(),
            Status__c = 'Completed',
            Document_Type__c = 'Old Type',
            Extracted_JSON__c = '{}',
            Analyzed_On__c = System.now()
        );
        Test.setMock(HttpCalloutMock.class, new DualMock(200, goodAnthropicBody()));
        Test.startTest();
        DocumentAnalysisService.AnalysisDTO dto =
            DocumentAnalysisService.analyze(docId(), true);
        Test.stopTest();

        System.assertEquals('Medical Record', dto.documentType, 'refreshed');
        System.assertEquals(1, [SELECT COUNT() FROM Document_Analysis__c], 'updated in place');
    }

    @isTest
    static void testUnsupportedType() {
        Document__c d = [SELECT Id, Name FROM Document__c LIMIT 1];
        d.Name = 'archive.zip';
        update d;

        Boolean threw = false;
        Test.startTest();
        try {
            DocumentAnalysisService.analyze(d.Id, false);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'unsupported type should throw');
    }

    @isTest
    static void testFailurePersistsFailedRecord() {
        Test.setMock(HttpCalloutMock.class, new DualMock(400, '{"error":{"message":"bad request"}}'));
        Boolean threw = false;
        Test.startTest();
        try {
            DocumentAnalysisService.analyze(docId(), false);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'should surface failure');
        Document_Analysis__c rec = [
            SELECT Status__c, Error__c FROM Document_Analysis__c WHERE Document__c = :docId()
        ];
        System.assertEquals('Failed', rec.Status__c);
        System.assertNotEquals(null, rec.Error__c);
    }

    @isTest
    static void testListDocuments() {
        Id intakeId = [SELECT Intake__c FROM Document__c LIMIT 1].Intake__c;
        Test.startTest();
        List<DocumentAnalysisController.FileRow> rows =
            DocumentAnalysisController.listDocuments(intakeId);
        Test.stopTest();
        System.assertEquals(1, rows.size());
        System.assertEquals(true, rows[0].analyzable, 'pdf is analyzable');
        System.assertEquals(false, rows[0].analyzed, 'not analyzed yet');
    }

    @isTest
    static void testControllerEndToEnd() {
        Test.setMock(HttpCalloutMock.class, new DualMock(200, goodAnthropicBody()));
        Test.startTest();
        DocumentAnalysisService.AnalysisDTO fresh =
            DocumentAnalysisController.analyzeDocument(docId(), false);
        DocumentAnalysisService.AnalysisDTO cached =
            DocumentAnalysisController.getAnalysis(docId());
        Test.stopTest();

        System.assertEquals('Completed', fresh.status, 'controller analyze');
        System.assertNotEquals(null, cached, 'controller getAnalysis returns cache');
        System.assertEquals('Medical Record', cached.documentType);
    }

    @isTest
    static void testHelpers() {
        // Extension is authoritative (MIME truncates in this org).
        System.assertEquals('document', DocumentAnalysisService.mediaBlockType('report.pdf', null));
        System.assertEquals('image', DocumentAnalysisService.mediaBlockType('scan.PNG', null));
        System.assertEquals(null, DocumentAnalysisService.mediaBlockType('notes.txt', null));
        // MIME fallback still works when there's no usable extension.
        System.assertEquals('image', DocumentAnalysisService.mediaBlockType('blob', 'image/jpeg'));
        System.assert(DocumentAnalysisService.isAnalyzable('photo.jpeg', null));

        Map<String, Object> f = DocumentAnalysisService.parseFacts(
            'Here is the JSON:\n```json\n{"summary":"ok"}\n``` thanks');
        System.assertEquals('ok', (String) f.get('summary'), 'strips fences/prose');
    }
}