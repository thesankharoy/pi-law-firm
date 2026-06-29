/**
 * Full-slice test for US71 lead-source quality forecasting: rollup + transparent score,
 * forecast + narration guardrail (accept/reject), spend-shift what-if, back-test, schedulers.
 */
@isTest
private class SourceQualitySliceTest {

    private static String pick(Schema.SObjectField f) {
        for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues())
            if (e.isActive()) return e.getValue();
        return null;
    }
    private static Id activeRt() {
        Schema.RecordTypeInfo rti = Intake__c.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get('Active_Intake');
        return rti == null ? null : rti.getRecordTypeId();
    }
    private static Intake__c intake(String status, String src) {
        Intake__c i = new Intake__c(RecordTypeId = activeRt(), Status__c = status,
            Incident_Type__c = pick(Intake__c.Incident_Type__c), Source__c = src);
        insert i;
        return i;
    }
    private static String srcVal() {
        return pick(Intake__c.Source__c);
    }

    // ── rollup + transparent score ───────────────────────────────────
    @isTest
    static void testRollup() {
        String src = srcVal();
        intake('Retainer Agreement Signed', src);
        Intake__c b = intake('Turned Down', src);
        insert new Loss_Analysis__c(Intake__c = b.Id, Source__c = src,
            Primary_Reason__c = 'Statute_Expired', Fault_Category__c = 'Case_Merits');
        insert new Marketing_Spend__c(Source__c = src, Period_Start__c = Date.today().addDays(-30),
            Period_End__c = Date.today(), Amount__c = 1000);

        Test.startTest();
        SourceRollupService.rebuild();
        Test.stopTest();

        Source_Quality_Snapshot__c q = [
            SELECT Leads__c, Signed__c, Sign_Rate__c, Lead_Fit_Rate__c, Cost_Per_Lead__c,
                   Cost_Per_Signed__c, Quality_Score__c, Score_Rationale__c
            FROM Source_Quality_Snapshot__c WHERE Source__c = :src LIMIT 1
        ];
        System.assertEquals(2, q.Leads__c.intValue());
        System.assertEquals(1, q.Signed__c.intValue());
        System.assertEquals(50, q.Sign_Rate__c.intValue());
        System.assertEquals(50, q.Lead_Fit_Rate__c.intValue());
        System.assertEquals(500, q.Cost_Per_Lead__c.intValue(), '1000/2 leads');
        System.assertEquals(1000, q.Cost_Per_Signed__c.intValue(), '1000/1 signed');
        System.assertNotEquals(null, q.Quality_Score__c);
        System.assert(String.isNotBlank(q.Score_Rationale__c));
    }

    // ── forecast + narration guardrail ───────────────────────────────
    @isTest
    static void testForecastNarrationAccepts() {
        insert new Win_Loss_Config__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Send_Email__c = true, Owner_User_Id__c = UserInfo.getUserId());
        String src = srcVal();
        intake('Retainer Agreement Signed', src);
        intake('Turned Down', src);
        insert new Marketing_Spend__c(Source__c = src, Period_Start__c = Date.today().addDays(-30),
            Period_End__c = Date.today(), Amount__c = 1000);

        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200,
            'Scale the strongest source and trim the weakest; concentrate budget where sign-through is best.'));
        Test.startTest();
        List<Source_Forecast__c> fcs = SourceForecastService.run();
        Test.stopTest();

        System.assert(!fcs.isEmpty());
        System.assertEquals('AI', [SELECT Guardrail_Status__c FROM Source_Forecast__c LIMIT 1].Guardrail_Status__c);
    }

    @isTest
    static void testForecastNarrationRejects() {
        String src = srcVal();
        intake('Retainer Agreement Signed', src);
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200, 'We will sign 8888 from this source.'));
        Test.startTest();
        SourceForecastService.run();
        Test.stopTest();
        System.assertEquals('Template', [SELECT Guardrail_Status__c FROM Source_Forecast__c LIMIT 1].Guardrail_Status__c);
    }

    // ── spend-shift what-if ──────────────────────────────────────────
    @isTest
    static void testSpendShift() {
        insert new List<Source_Quality_Snapshot__c>{
            new Source_Quality_Snapshot__c(Source__c = 'A', Cost_Per_Lead__c = 100, Sign_Rate__c = 20,
                Period_Start__c = Date.today(), Period_End__c = Date.today()),
            new Source_Quality_Snapshot__c(Source__c = 'B', Cost_Per_Lead__c = 50, Sign_Rate__c = 40,
                Period_Start__c = Date.today(), Period_End__c = Date.today())
        };
        Test.startTest();
        SourceSpendShiftCalculator.Result r = SourceSpendShiftCalculator.whatIf('A', 'B', 1000);
        Test.stopTest();
        System.assertEquals(2, r.fromLost.intValue(), '1000/100 * 20% = 2 lost');
        System.assertEquals(8, r.toGained.intValue(), '1000/50 * 40% = 8 gained');
        System.assertEquals(6, r.net.intValue());
    }

    // ── back-test ────────────────────────────────────────────────────
    @isTest
    static void testBackTest() {
        String src = srcVal();
        Intake__c g = intake('Working', src);
        Source_Forecast__c f = new Source_Forecast__c(Source__c = src, Horizon_Days__c = 30,
            Projected_Signed__c = 2, Generated_At__c = System.now().addDays(-100));
        insert f;
        insert new Stage_Transition__c(Intake__c = g.Id, To_Status__c = 'Retainer Agreement Signed',
            Occurred_At__c = System.now().addDays(-85));

        Test.startTest();
        SourceBackTestService.run();
        Test.stopTest();

        Source_Forecast__c after = [SELECT Actual_Signed__c, Error_Pct__c FROM Source_Forecast__c WHERE Id = :f.Id];
        System.assertEquals(1, after.Actual_Signed__c.intValue());
        System.assertEquals(100, after.Error_Pct__c.intValue());
    }

    // ── schedulers / enqueue ─────────────────────────────────────────
    @isTest
    static void testSchedulerAndEnqueue() {
        Test.startTest();
        Id jobId = SourceForecastService.enqueue();
        String cron = System.schedule('Source Forecast Test', '0 0 7 1 1 ? 2042', new SourceForecastScheduler());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
        System.assertNotEquals(null, cron);
    }
}