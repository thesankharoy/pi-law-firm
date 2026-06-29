/**
 * Full-slice test for the FAQ / Objection Knowledge Base (US72). Claude is faked with the
 * shared AnthropicCalloutMock, so extraction, clustering, drafting, curation+versioning,
 * lookup, batch, and scheduler are all exercised deterministically.
 */
@isTest
private class FAQSliceTest {

    private static String firstInc() {
        for (Schema.PicklistEntry e : Intake__c.Incident_Type__c.getDescribe().getPicklistValues())
            if (e.isActive()) return e.getValue();
        return null;
    }
    private static Id activeRt() {
        Schema.RecordTypeInfo rti = Intake__c.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get('Active_Intake');
        return rti == null ? null : rti.getRecordTypeId();
    }
    private static Intake__c intake(String status, String transcript) {
        Intake__c i = new Intake__c(RecordTypeId = activeRt(), Status__c = status,
            Incident_Type__c = firstInc(), Transcript__c = transcript);
        insert i;
        return i;
    }
    private static Intake__c requery(Id id) {
        return [SELECT Id, Status__c, Transcript__c, Incident_Description__c FROM Intake__c WHERE Id = :id];
    }

    private static final String TRANSCRIPT =
        'Client: the fee is too high for me. Agent: we only get paid if you win. '
        + 'Client: how long will it take? Agent: usually several months.';

    private static final String ITEMS_JSON =
        '{"items":[' +
        '{"kind":"Objection","objectionType":"Fee_Percentage","text":"the fee is too high","responseGiven":"we only get paid if you win"},' +
        '{"kind":"Question","category":"Timeline","text":"how long will it take","responseGiven":"usually several months"}' +
        ']}';

    // ── extraction ───────────────────────────────────────────────────
    @isTest
    static void testExtraction() {
        Intake__c i = intake('Retainer Agreement Signed', TRANSCRIPT);
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200, ITEMS_JSON));

        Test.startTest();
        List<FAQ_Candidate__c> cs = FAQExtractionService.extract(requery(i.Id), true);
        Test.stopTest();

        System.assertEquals(2, cs.size());
        Map<String, FAQ_Candidate__c> byKind = new Map<String, FAQ_Candidate__c>();
        for (FAQ_Candidate__c c : cs) byKind.put(c.Kind__c, c);
        System.assertEquals('OBJ:Fee_Percentage', byKind.get('Objection').Cluster_Key__c);
        System.assertEquals(true, byKind.get('Objection').Led_To_Signing__c);
        System.assertEquals(false, byKind.get('Objection').Needs_Review__c, 'verbatim quote verified');
        System.assert(byKind.get('Question').Cluster_Key__c.startsWith('Q:'));
    }

    @isTest
    static void testExtractionEvidenceGuard() {
        Intake__c i = intake('Turned Down', 'totally unrelated transcript content here');
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200, ITEMS_JSON));

        Test.startTest();
        List<FAQ_Candidate__c> cs = FAQExtractionService.extract(requery(i.Id), false);
        Test.stopTest();

        for (FAQ_Candidate__c c : cs) {
            System.assertEquals(true, c.Needs_Review__c, 'quote not in transcript -> review');
        }
    }

    // ── clustering ───────────────────────────────────────────────────
    @isTest
    static void testClustering() {
        Intake__c i = intake('Turned Down', TRANSCRIPT);
        insert new List<FAQ_Candidate__c>{
            new FAQ_Candidate__c(Intake__c=i.Id, Kind__c='Objection', Objection_Type__c='Fee_Percentage',
                Cluster_Key__c='OBJ:Fee_Percentage', Raw_Text__c='the fee is too high', Led_To_Signing__c=true, Needs_Review__c=false),
            new FAQ_Candidate__c(Intake__c=i.Id, Kind__c='Objection', Objection_Type__c='Fee_Percentage',
                Cluster_Key__c='OBJ:Fee_Percentage', Raw_Text__c='thirty three percent is a lot', Led_To_Signing__c=false, Needs_Review__c=false)
        };

        Test.startTest();
        FAQService.runClustering();
        Test.stopTest();

        FAQ_Entry__c e = [SELECT Frequency__c, Handled_Success_Rate__c, Status__c, Objection_Type__c
            FROM FAQ_Entry__c WHERE Cluster_Key__c='OBJ:Fee_Percentage'];
        System.assertEquals(2, e.Frequency__c.intValue());
        System.assertEquals(50, e.Handled_Success_Rate__c.intValue());
        System.assertEquals('Draft', e.Status__c);
    }

    // ── batch end-to-end ─────────────────────────────────────────────
    @isTest
    static void testBatch() {
        intake('Retainer Agreement Signed', TRANSCRIPT);
        intake('Turned Down', TRANSCRIPT);
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200, ITEMS_JSON));

        Test.startTest();
        Database.executeBatch(new FAQMiningBatch(), 5);
        Test.stopTest();

        System.assertEquals(4, [SELECT COUNT() FROM FAQ_Candidate__c], '2 items x 2 intakes');
        System.assert([SELECT COUNT() FROM FAQ_Entry__c] >= 1, 'finish rebuilt clusters');
    }

    // ── drafting ─────────────────────────────────────────────────────
    @isTest
    static void testDraftJob() {
        FAQService.minFreq = 1;
        Intake__c i = intake('Retainer Agreement Signed', TRANSCRIPT);
        insert new FAQ_Candidate__c(Intake__c=i.Id, Kind__c='Objection', Objection_Type__c='Fee_Percentage',
            Cluster_Key__c='OBJ:Fee_Percentage', Raw_Text__c='the fee is too high',
            Response_Given__c='we work on contingency', Led_To_Signing__c=true, Needs_Review__c=false);
        insert new FAQ_Entry__c(Cluster_Key__c='OBJ:Fee_Percentage', Category__c='Objection',
            Objection_Type__c='Fee_Percentage', Title__c='Objection: Fee Percentage', Frequency__c=1,
            Handled_Success_Rate__c=100, Status__c='Draft');

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200, 'Reassure the client we only get paid if they win.'));
        System.enqueueJob(new FAQDraftJob());
        Test.stopTest();

        FAQ_Entry__c e = [SELECT Recommended_Response__c FROM FAQ_Entry__c WHERE Cluster_Key__c='OBJ:Fee_Percentage'];
        System.assert(String.isNotBlank(e.Recommended_Response__c), 'draft generated');
    }

    // ── curation + versioning ────────────────────────────────────────
    @isTest
    static void testCurationAndVersioning() {
        FAQ_Entry__c e = new FAQ_Entry__c(Cluster_Key__c='OBJ:Need_To_Think', Category__c='Objection',
            Objection_Type__c='Need_To_Think', Title__c='Objection: Need to Think', Frequency__c=3,
            Handled_Success_Rate__c=40, Status__c='Draft', Recommended_Response__c='draft text');
        insert e;

        Test.startTest();
        FAQCurationController.updateResponse(e.Id, 'edited best practice text');
        FAQCurationController.approveEntry(e.Id);
        Test.stopTest();

        FAQ_Entry__c after = [SELECT Status__c, Version__c, Recommended_Response__c, Approved_By__c FROM FAQ_Entry__c WHERE Id=:e.Id];
        System.assertEquals('Approved', after.Status__c);
        System.assertEquals(2, after.Version__c.intValue(), 'edit + approve = v2');
        System.assertEquals(UserInfo.getUserId(), after.Approved_By__c);
        System.assertEquals(2, [SELECT COUNT() FROM FAQ_Entry_Version__c WHERE FAQ_Entry__c=:e.Id], 'audit snapshots');
    }

    // ── lookup + lists + scheduler ───────────────────────────────────
    @isTest
    static void testLookupListsAndScheduler() {
        insert new FAQ_Entry__c(Cluster_Key__c='OBJ:Distrust', Category__c='Objection', Objection_Type__c='Distrust',
            Title__c='Objection: Distrust', Frequency__c=5, Handled_Success_Rate__c=60, Status__c='Approved',
            Recommended_Response__c='Build trust by...');
        insert new FAQ_Entry__c(Cluster_Key__c='OBJ:Why_Your_Firm', Category__c='Objection', Objection_Type__c='Why_Your_Firm',
            Title__c='Objection: Why Your Firm', Frequency__c=4, Handled_Success_Rate__c=30, Status__c='Draft');

        Test.startTest();
        FAQ_Entry__c approved = FAQLookupService.getApprovedForObjection('Distrust');
        List<FAQCurationController.EntryRow> drafts = FAQCurationController.getDrafts();
        List<FAQCurationController.EntryRow> gaps = FAQCurationController.getCoverageGaps();
        Id mineId = FAQService.runMining();
        String cron = System.schedule('FAQ Test', '0 0 0 1 1 ? 2042', new FAQScheduler());
        Test.stopTest();

        System.assertNotEquals(null, approved, 'approved entry served');
        System.assertEquals(1, drafts.size(), 'one draft listed');
        System.assert(gaps.size() >= 1, 'draft high-freq is a coverage gap');
        System.assertNotEquals(null, mineId);
        System.assertNotEquals(null, cron);
    }
}