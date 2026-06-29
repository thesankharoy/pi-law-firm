/**
 * Full-pipeline test for Win/Loss Mining + Objection Analytics. Claude is faked with the
 * shared AnthropicCalloutMock, so every branch (taxonomy guard, evidence guard, low
 * confidence, off-taxonomy, transcript fallback, batch, aggregation, narration guardrail
 * pass/reject/error, delivery, schedulers) is exercised deterministically and offline.
 *
 * Intakes use the Active_Intake record type (when present) and a terminal status so the
 * IntakeTrigger assignment handler is skipped. Swap to your TestDataFactory if needed.
 */
@isTest
private class WinLossSliceTest {

    // ── helpers ──────────────────────────────────────────────────────
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

    private static Intake__c lostIntake(String transcript, String status) {
        Intake__c i = new Intake__c(
            RecordTypeId = activeRt(),
            Status__c = status,
            Incident_Type__c = firstInc(),
            Transcript__c = transcript
        );
        insert i;
        return i;
    }

    private static Intake__c requery(Id id) {
        return [
            SELECT Id, Incident_Type__c, OwnerId, Transcript__c, Incident_Description__c,
                   Source__c, Turn_Down_Reason__c, Turn_Down_Details__c
            FROM Intake__c WHERE Id = :id
        ];
    }

    private static String extractionJson(String reason, String conf, String quote, String objType, String objQuote) {
        return '{"primaryReason":"' + reason + '","confidence":' + conf
            + ',"evidenceQuote":"' + quote + '","summary":"why it was lost",'
            + '"objections":[{"type":"' + objType + '","quote":"' + objQuote + '"}]}';
    }

    // ── taxonomy guard (Guardrail 1) ─────────────────────────────────
    @isTest
    static void testTaxonomyGuard() {
        System.assertEquals('Slow_Response_Or_Experience',
            WinLossTaxonomy.safeReason('Slow_Response_Or_Experience'));
        System.assertEquals('Unclassified', WinLossTaxonomy.safeReason('Banana'));
        System.assertEquals('Other', WinLossTaxonomy.safeObjection('Nonsense'));
        System.assertEquals('Process', WinLossTaxonomy.faultFor('Slow_Response_Or_Experience'));
        System.assertEquals('Case_Merits', WinLossTaxonomy.faultFor('Statute_Expired'));
        System.assertEquals('Client_Choice', WinLossTaxonomy.faultFor('Fee_Or_Cost_Concern'));
        System.assertEquals('Unknown', WinLossTaxonomy.faultFor('Unclassified'));
    }

    // ── extraction happy path ────────────────────────────────────────
    @isTest
    static void testExtractionHappyPath() {
        Intake__c i = lostIntake('Caller said: you never called me back for two weeks.', 'Turned Down');
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200,
            extractionJson('Slow_Response_Or_Experience', '0.9', 'you never called me back', 'Why_Your_Firm', 'why should I trust you')));

        Test.startTest();
        LossExtractionService.ExtractionResult r = LossExtractionService.extract(requery(i.Id));
        Test.stopTest();

        System.assertEquals('Slow_Response_Or_Experience', r.analysis.Primary_Reason__c);
        System.assertEquals('Process', r.analysis.Fault_Category__c, 'fault derived deterministically');
        System.assertEquals(false, r.analysis.Needs_Review__c, 'verified quote + confidence');
        System.assertEquals(1, r.objections.size());
        System.assertEquals('Why_Your_Firm', r.objections[0].Objection_Type__c);
    }

    // ── evidence guard (Guardrail 2) ─────────────────────────────────
    @isTest
    static void testEvidenceGuardFlagsReview() {
        Intake__c i = lostIntake('The client simply chose a competitor.', 'Turned Down');
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200,
            extractionJson('Chose_Another_Firm', '0.95', 'a quote that is absent from the transcript', 'Why_Your_Firm', 'q')));

        Test.startTest();
        LossExtractionService.ExtractionResult r = LossExtractionService.extract(requery(i.Id));
        Test.stopTest();

        System.assertEquals(true, r.analysis.Needs_Review__c, 'unverifiable quote -> review');
    }

    @isTest
    static void testLowConfidenceFlagsReview() {
        Intake__c i = lostIntake('the fee is too high for me to accept', 'Turned Down');
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200,
            extractionJson('Fee_Or_Cost_Concern', '0.2', 'the fee is too high', 'Fee_Percentage', 'too high')));

        Test.startTest();
        LossExtractionService.ExtractionResult r = LossExtractionService.extract(requery(i.Id));
        Test.stopTest();

        System.assertEquals(true, r.analysis.Needs_Review__c, 'low confidence -> review');
        System.assertEquals('Client_Choice', r.analysis.Fault_Category__c);
    }

    // ── off-taxonomy (Guardrail 1 in extraction) ─────────────────────
    @isTest
    static void testOffTaxonomySnapsToDefault() {
        Intake__c i = lostIntake('some transcript text here', 'Turned Down');
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200,
            extractionJson('TotallyMadeUp', '0.9', 'some transcript text', 'AlsoFake', 'q')));

        Test.startTest();
        LossExtractionService.ExtractionResult r = LossExtractionService.extract(requery(i.Id));
        Test.stopTest();

        System.assertEquals('Unclassified', r.analysis.Primary_Reason__c);
        System.assertEquals('Unknown', r.analysis.Fault_Category__c);
        System.assertEquals('Other', r.objections[0].Objection_Type__c);
        System.assertEquals(true, r.analysis.Needs_Review__c);
    }

    // ── transcript fallback to Incident_Description__c ───────────────
    @isTest
    static void testTranscriptFallback() {
        Intake__c i = new Intake__c(
            RecordTypeId = activeRt(), Status__c = 'Turned Down', Incident_Type__c = firstInc(),
            Incident_Description__c = 'the fee is too high for me');
        insert i; // no Transcript__c
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200,
            extractionJson('Fee_Or_Cost_Concern', '0.8', 'the fee is too high', 'Fee_Percentage', 'too high')));

        Test.startTest();
        LossExtractionService.ExtractionResult r = LossExtractionService.extract(requery(i.Id));
        Test.stopTest();

        System.assertEquals('Fee_Or_Cost_Concern', r.analysis.Primary_Reason__c, 'classified from description');
        System.assertEquals(false, r.analysis.Needs_Review__c);
    }

    // ── batch end-to-end + status filter + dedup ─────────────────────
    @isTest
    static void testBatchEndToEnd() {
        lostIntake('you never called me back at all', 'Turned Down');
        lostIntake('you never called me back at all', 'Referred Out');
        // non-lost intake must be ignored
        lostIntake('you never called me back at all', 'Qualified');

        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200,
            extractionJson('Slow_Response_Or_Experience', '0.9', 'you never called me back', 'Why_Your_Firm', 'q')));

        Test.startTest();
        Database.executeBatch(new LossMiningBatch(), 5);
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Loss_Analysis__c], 'only the two lost intakes');
        System.assertEquals(2, [SELECT COUNT() FROM Objection__c]);

        // dedup: a second run creates nothing new
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200,
            extractionJson('Slow_Response_Or_Experience', '0.9', 'you never called me back', 'Why_Your_Firm', 'q')));
        Database.executeBatch(new LossMiningBatch(), 5);
        System.assertEquals(2, [SELECT COUNT() FROM Loss_Analysis__c], 'dedup holds');
    }

    // ── aggregation (deterministic) ──────────────────────────────────
    @isTest
    static void testAggregation() {
        insert new List<Loss_Analysis__c>{
            new Loss_Analysis__c(Primary_Reason__c = 'Slow_Response_Or_Experience', Fault_Category__c = 'Process'),
            new Loss_Analysis__c(Primary_Reason__c = 'Slow_Response_Or_Experience', Fault_Category__c = 'Process'),
            new Loss_Analysis__c(Primary_Reason__c = 'Statute_Expired', Fault_Category__c = 'Case_Merits')
        };
        insert new List<Objection__c>{
            new Objection__c(Objection_Type__c = 'Fee_Percentage'),
            new Objection__c(Objection_Type__c = 'Fee_Percentage'),
            new Objection__c(Objection_Type__c = 'Need_To_Think')
        };

        Test.startTest();
        LossAggregationService.Aggregates a = LossAggregationService.aggregate(90);
        Test.stopTest();

        System.assertEquals(3, a.total);
        System.assertEquals(2, a.processCount);
        System.assertEquals(66, a.processPct);
        System.assertEquals('Slow_Response_Or_Experience', a.topReason);
        System.assertEquals(2, a.topReasonCount);
        System.assertEquals('Fee_Percentage', a.topObjection);
    }

    // ── narration guardrail (Guardrail 3) ────────────────────────────
    private static LossAggregationService.Aggregates seededAggregates() {
        insert new List<Loss_Analysis__c>{
            new Loss_Analysis__c(Primary_Reason__c = 'Slow_Response_Or_Experience', Fault_Category__c = 'Process'),
            new Loss_Analysis__c(Primary_Reason__c = 'Slow_Response_Or_Experience', Fault_Category__c = 'Process'),
            new Loss_Analysis__c(Primary_Reason__c = 'Statute_Expired', Fault_Category__c = 'Case_Merits')
        };
        return LossAggregationService.aggregate(90);
    }

    @isTest
    static void testNarrationGuardrailAccepts() {
        LossAggregationService.Aggregates a = seededAggregates();
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200,
            'Of 3 losses, 2 (66%) were Process and fixable. Focus there first.'));

        Test.startTest();
        LossNarrationService.NarrationResult n = LossNarrationService.narrate(a);
        Test.stopTest();

        System.assertEquals('AI', n.source, 'clean figures accepted');
    }

    @isTest
    static void testNarrationGuardrailRejectsInvented() {
        LossAggregationService.Aggregates a = seededAggregates();
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200,
            'We actually lost 4521 cases, a disaster.'));

        Test.startTest();
        LossNarrationService.NarrationResult n = LossNarrationService.narrate(a);
        Test.stopTest();

        System.assertEquals('Template', n.source, 'invented figure rejected');
        System.assert(!n.narrative.contains('4521'));
    }

    @isTest
    static void testNarrationFallsBackOnHttpError() {
        LossAggregationService.Aggregates a = seededAggregates();
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(400, null));

        Test.startTest();
        LossNarrationService.NarrationResult n = LossNarrationService.narrate(a);
        Test.stopTest();

        System.assertEquals('Template', n.source);
        System.assert(String.isNotBlank(n.narrative));
    }

    // ── delivery + narration job ─────────────────────────────────────
    @isTest
    static void testNarrationJobDelivers() {
        seededAggregates();
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200,
            'Of 3 losses, 2 (66%) were Process and fixable.'));

        Test.startTest();
        System.enqueueJob(new LossNarrationJob(90));
        Test.stopTest();

        Loss_Insight__c ins = [
            SELECT Total_Losses__c, Process_Count__c, Narrative_Source__c, Narrative__c
            FROM Loss_Insight__c LIMIT 1
        ];
        System.assertEquals(3, ins.Total_Losses__c.intValue());
        System.assertEquals(2, ins.Process_Count__c.intValue());
        System.assertEquals('AI', ins.Narrative_Source__c);
    }

    // ── delivery with the email branch enabled (coverage for sendEmail) ──
    @isTest
    static void testDeliveryWithEmail() {
        insert new Win_Loss_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Send_Email__c = true,
            Owner_User_Id__c = UserInfo.getUserId()
        );
        LossAggregationService.Aggregates a = seededAggregates();
        // No mock -> callout fails -> deterministic template, then deliver (bell + email).
        LossNarrationService.NarrationResult n = LossNarrationService.narrate(a);

        Test.startTest();
        Loss_Insight__c ins = WinLossAlertService.deliver(n, a);
        Test.stopTest();

        System.assertNotEquals(null, ins.Id, 'insight delivered with email enabled');
        System.assertEquals(3, ins.Total_Losses__c.intValue());
    }

    // ── schedulers + entry service ───────────────────────────────────
    @isTest
    static void testSchedulersAndService() {
        Test.startTest();
        Id batchId = WinLossService.runExtraction();
        Id jobId = WinLossService.runNarrationLastDays(30);
        String c1 = System.schedule('WL Mining Test', '0 0 2 1 1 ? 2042', new LossMiningScheduler());
        String c2 = System.schedule('WL Digest Test', '0 0 7 1 1 ? 2042', new LossNarrationScheduler());
        Test.stopTest();

        System.assertNotEquals(null, batchId);
        System.assertNotEquals(null, jobId);
        System.assertNotEquals(null, c1);
        System.assertNotEquals(null, c2);
    }
}