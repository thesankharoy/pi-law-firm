/**
 * Read-only data source for the "Revenue at Risk" home/app component. Returns every
 * still-at-risk leak (Open or Alerted), ranked by dollars, plus headline totals.
 * Cacheable so the card loads instantly and refreshes via getRecordNotifyChange / refreshApex.
 */
public with sharing class RevenueLeakDashboardController {

    public class LeakRow {
        @AuraEnabled public Id leakId;
        @AuraEnabled public Id intakeId;
        @AuraEnabled public String intakeName;
        @AuraEnabled public String client;
        @AuraEnabled public String matter;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String severity;
        @AuraEnabled public Integer daysOverdue;
    }

    public class Summary {
        @AuraEnabled public Decimal totalAtRisk = 0;
        @AuraEnabled public Integer openCount = 0;
        @AuraEnabled public Integer criticalCount = 0;
        @AuraEnabled public List<LeakRow> rows = new List<LeakRow>();
    }

    @AuraEnabled(cacheable=true)
    public static Summary getOpenLeaks() {
        Summary s = new Summary();
        for (Revenue_Leak__c l : [
            SELECT Id, Intake__c, Intake__r.Name, Intake__r.Incident_Type__c, Intake__r.Client__r.Name,
                   Estimated_Value__c, Severity__c, Days_Overdue__c
            FROM Revenue_Leak__c
            WHERE Status__c IN ('Open', 'Alerted')
            ORDER BY Estimated_Value__c DESC NULLS LAST
            LIMIT 50
        ]) {
            LeakRow r = new LeakRow();
            r.leakId = l.Id;
            r.intakeId = l.Intake__c;
            r.intakeName = l.Intake__r != null ? l.Intake__r.Name : null;
            r.client = (l.Intake__r != null && l.Intake__r.Client__r != null && l.Intake__r.Client__r.Name != null)
                ? l.Intake__r.Client__r.Name : 'Unknown client';
            r.matter = (l.Intake__r != null && String.isNotBlank(l.Intake__r.Incident_Type__c))
                ? l.Intake__r.Incident_Type__c : 'Unspecified';
            r.amount = l.Estimated_Value__c == null ? 0 : l.Estimated_Value__c;
            r.severity = l.Severity__c;
            r.daysOverdue = l.Days_Overdue__c == null ? 0 : Integer.valueOf(l.Days_Overdue__c);

            s.rows.add(r);
            s.totalAtRisk += r.amount;
            s.openCount++;
            if (r.severity == 'Critical') s.criticalCount++;
        }
        return s;
    }
}