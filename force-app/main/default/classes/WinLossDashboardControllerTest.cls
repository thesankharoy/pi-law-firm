@isTest
private class WinLossDashboardControllerTest {

    @testSetup
    static void setup() {
        insert new List<Loss_Analysis__c>{
            new Loss_Analysis__c(Primary_Reason__c = 'Slow_Response_Or_Experience', Fault_Category__c = 'Process', Needs_Review__c = false),
            new Loss_Analysis__c(Primary_Reason__c = 'Slow_Response_Or_Experience', Fault_Category__c = 'Process', Needs_Review__c = false),
            new Loss_Analysis__c(Primary_Reason__c = 'Statute_Expired', Fault_Category__c = 'Case_Merits', Needs_Review__c = false),
            new Loss_Analysis__c(Primary_Reason__c = 'Unclassified', Fault_Category__c = 'Unknown', Confidence__c = 0.2, Needs_Review__c = true)
        };
        insert new List<Objection__c>{
            new Objection__c(Objection_Type__c = 'Fee_Percentage'),
            new Objection__c(Objection_Type__c = 'Need_To_Think')
        };
    }

    @isTest
    static void testLossSummary() {
        Test.startTest();
        WinLossDashboardController.LossSummary s = WinLossDashboardController.getLossSummary(90);
        Test.stopTest();

        System.assertEquals(4, s.total);
        System.assertEquals(2, s.processCount);
        System.assertEquals(50, s.processPct);
        System.assert(!s.faults.isEmpty(), 'fault buckets present');
        System.assertEquals('Slow Response Or Experience', s.reasons[0].label, 'top reason first');
        System.assertEquals(2, s.reasons[0].count);
        System.assert(!s.objections.isEmpty(), 'objection buckets present');
    }

    @isTest
    static void testLossSummaryDefaultLookback() {
        Test.startTest();
        WinLossDashboardController.LossSummary s = WinLossDashboardController.getLossSummary(null);
        Test.stopTest();
        System.assert(s.lookbackDays >= 1, 'falls back to configured lookback');
    }

    @isTest
    static void testNeedsReviewAndMarkReviewed() {
        Test.startTest();
        List<WinLossDashboardController.ReviewRow> rows = WinLossDashboardController.getNeedsReview();
        System.assertEquals(1, rows.size(), 'only the flagged record');
        System.assertEquals('Unclassified', rows[0].reason);

        WinLossDashboardController.markReviewed(rows[0].id);
        Test.stopTest();

        System.assertEquals(0, WinLossDashboardController.getNeedsReview().size(), 'cleared after review');
        System.assertEquals(false, [SELECT Needs_Review__c FROM Loss_Analysis__c WHERE Id = :rows[0].id].Needs_Review__c);
    }
}