@isTest
private class RevenueLeakDashboardControllerTest {

    private static String firstInc() {
        for (Schema.PicklistEntry e : Intake__c.Incident_Type__c.getDescribe().getPicklistValues())
            if (e.isActive()) return e.getValue();
        return null;
    }

    @isTest
    static void testGetOpenLeaks() {
        Id rt = Intake__c.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get('Active_Intake').getRecordTypeId();
        Intake__c i = new Intake__c(
            RecordTypeId = rt, Status__c = 'Retainer Agreement Sent', Incident_Type__c = firstInc());
        insert i;

        insert new List<Revenue_Leak__c>{
            new Revenue_Leak__c(Intake__c = i.Id, Leak_Type__c = 'Unsigned Retainer', Status__c = 'Open',
                Estimated_Value__c = 16250, Severity__c = 'High', Days_Overdue__c = 2, Alerted__c = false),
            new Revenue_Leak__c(Intake__c = i.Id, Leak_Type__c = 'Unsigned Retainer', Status__c = 'Alerted',
                Estimated_Value__c = 32000, Severity__c = 'Critical', Days_Overdue__c = 5, Alerted__c = true),
            // Recovered leak must be excluded from the at-risk view.
            new Revenue_Leak__c(Intake__c = i.Id, Leak_Type__c = 'Unsigned Retainer', Status__c = 'Recovered',
                Estimated_Value__c = 9999, Severity__c = 'Low', Days_Overdue__c = 1, Alerted__c = true)
        };

        Test.startTest();
        RevenueLeakDashboardController.Summary s = RevenueLeakDashboardController.getOpenLeaks();
        Test.stopTest();

        System.assertEquals(2, s.openCount, 'only Open + Alerted counted');
        System.assertEquals(1, s.criticalCount);
        System.assertEquals(48250, s.totalAtRisk.intValue(), 'sum of at-risk estimates');
        System.assertEquals(2, s.rows.size());
        System.assertEquals(32000, s.rows[0].amount.intValue(), 'ranked by amount desc');
        System.assertNotEquals(null, s.rows[0].matter, 'matter populated');
    }
}