/**
 * Full-slice test for US70 conversion forecasting: transition logging, the deterministic rate
 * model, forecast + confidence bands, the narration guardrail (accept/reject), delivery,
 * back-test, backfill, and schedulers. Claude is faked with AnthropicCalloutMock.
 */
@isTest
private class ConversionForecastSliceTest {

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
    private static Intake__c intake(String status) {
        Intake__c i = new Intake__c(RecordTypeId = activeRt(), Status__c = status, Incident_Type__c = firstInc());
        insert i;
        return i;
    }

    /** Seeds a signed and a lost intake that both passed through 'Working' → rate('Working')=0.5. */
    private static void seedHistory() {
        Intake__c a = intake('Retainer Agreement Signed');
        Intake__c b = intake('Turned Down');
        insert new List<Stage_Transition__c>{
            new Stage_Transition__c(Intake__c = a.Id, To_Status__c = 'Working', Occurred_At__c = System.now().addDays(-5)),
            new Stage_Transition__c(Intake__c = b.Id, To_Status__c = 'Working', Occurred_At__c = System.now().addDays(-5))
        };
    }

    // ── transition trigger ───────────────────────────────────────────
    @isTest
    static void testTransitionTriggerLogs() {
        Intake__c i = intake('Working');
        System.assertEquals(1, [SELECT COUNT() FROM Stage_Transition__c WHERE Intake__c = :i.Id], 'insert logged');
        i.Status__c = 'Qualified';
        update i;
        System.assertEquals(2, [SELECT COUNT() FROM Stage_Transition__c WHERE Intake__c = :i.Id], 'update logged');
    }

    // ── rate model ───────────────────────────────────────────────────
    @isTest
    static void testRateModel() {
        seedHistory();
        Test.startTest();
        ConversionRateService.Rates r = ConversionRateService.compute(90);
        Test.stopTest();
        System.assert(r.signRate.containsKey('Working'), 'Working stage present');
        System.assert(r.signRate.get('Working') == 0.5, 'half of Working intakes signed');
        System.assertEquals(2, r.sample.get('Working'));
    }

    // ── forecast + narration guardrail ───────────────────────────────
    @isTest
    static void testForecastNarrationAccepts() {
        seedHistory();
        intake('Working'); // open pipeline
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200,
            'The pipeline is steady; focus the team on later-stage matters to convert them.'));
        Test.startTest();
        List<Conversion_Forecast__c> fcs = ConversionForecastService.run();
        Test.stopTest();
        System.assertEquals(3, fcs.size(), 'three horizons');
        System.assertEquals(3, [SELECT COUNT() FROM Conversion_Forecast__c]);
        System.assertEquals('AI', [SELECT Guardrail_Status__c FROM Conversion_Forecast__c LIMIT 1].Guardrail_Status__c);
    }

    @isTest
    static void testForecastNarrationRejects() {
        seedHistory();
        intake('Working');
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200, 'We expect 9999 signings, incredible.'));
        Test.startTest();
        ConversionForecastService.run();
        Test.stopTest();
        System.assertEquals('Template', [SELECT Guardrail_Status__c FROM Conversion_Forecast__c LIMIT 1].Guardrail_Status__c,
            'invented figure rejected');
    }

    // ── back-test ────────────────────────────────────────────────────
    @isTest
    static void testBackTest() {
        Conversion_Forecast__c f = new Conversion_Forecast__c(
            Period_Start__c = Date.today().addDays(-100), Period_End__c = Date.today().addDays(-10),
            Horizon_Days__c = 90, Projected_Signed__c = 2, Guardrail_Status__c = 'Template', Generated_At__c = System.now());
        insert f;
        insert new Stage_Transition__c(To_Status__c = 'Retainer Agreement Signed', Occurred_At__c = System.now().addDays(-50));

        Test.startTest();
        ForecastBackTestService.run();
        Test.stopTest();

        Forecast_Accuracy__c a = [SELECT Predicted__c, Actual__c, Error_Pct__c FROM Forecast_Accuracy__c WHERE Forecast__c = :f.Id];
        System.assertEquals(2, a.Predicted__c.intValue());
        System.assertEquals(1, a.Actual__c.intValue());
        System.assertEquals(100, a.Error_Pct__c.intValue(), 'predicted 2 vs actual 1 = 100% error');
    }

    // ── backfill ─────────────────────────────────────────────────────
    @isTest
    static void testBackfill() {
        Intake__c i = intake('Working');
        delete [SELECT Id FROM Stage_Transition__c WHERE Intake__c = :i.Id];

        Test.startTest();
        Database.executeBatch(new StageTransitionBackfillBatch(), 50);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Stage_Transition__c WHERE Intake__c = :i.Id], 'baseline seeded');
    }

    // ── schedulers / enqueue ─────────────────────────────────────────
    @isTest
    static void testSchedulersAndEnqueue() {
        Test.startTest();
        Id jobId = ConversionForecastService.enqueue();
        String cron = System.schedule('Forecast Test', '0 0 7 1 1 ? 2042', new ConversionForecastScheduler());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
        System.assertNotEquals(null, cron);
    }
}