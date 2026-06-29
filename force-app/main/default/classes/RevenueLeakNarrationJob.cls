/**
 * Queueable (callout-allowed) that narrates every Open, not-yet-alerted leak and
 * delivers the digest. Runs in its own transaction so the callout is clean of DML.
 */
public class RevenueLeakNarrationJob implements Queueable, Database.AllowsCallouts {

    public void execute(QueueableContext ctx) {
        List<Revenue_Leak__c> open = [
            SELECT Id, Name, Intake__c, Leak_Type__c, Severity__c,
                   Estimated_Value__c, Expected_Case_Value__c, Sign_Probability__c, Days_Overdue__c,
                   Intake__r.Name, Intake__r.Incident_Type__c, Intake__r.Lead_Source_Channel__c,
                   Intake__r.Client__r.Name
            FROM Revenue_Leak__c
            WHERE Status__c = 'Open' AND Alerted__c = false
            ORDER BY Estimated_Value__c DESC NULLS LAST
        ];
        if (open.isEmpty()) return;

        RevenueLeakNarrationService.NarrationResult n = RevenueLeakNarrationService.narrate(open);
        RevenueLeakAlertService.deliver(n);
    }
}