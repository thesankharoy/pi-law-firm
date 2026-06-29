/**
 * Per-source back-test (US71-8): for each Source_Forecast whose horizon has closed and has no
 * actual yet, counts the signings that actually occurred for that source in the horizon window
 * (from Stage_Transition__c via the intake's Source) and records actual + absolute error %.
 */
public with sharing class SourceBackTestService {

    public static void run() {
        List<Source_Forecast__c> due = [
            SELECT Id, Source__c, Horizon_Days__c, Projected_Signed__c, Generated_At__c
            FROM Source_Forecast__c
            WHERE Actual_Signed__c = null AND Generated_At__c != null
        ];
        if (due.isEmpty()) return;

        List<Source_Forecast__c> toUpdate = new List<Source_Forecast__c>();
        for (Source_Forecast__c f : due) {
            Integer h = f.Horizon_Days__c == null ? 0 : f.Horizon_Days__c.intValue();
            DateTime endDt = f.Generated_At__c.addDays(h);
            if (endDt > System.now()) continue; // window not closed yet

            Integer actual = [
                SELECT COUNT()
                FROM Stage_Transition__c
                WHERE To_Status__c IN :ConversionRateService.SIGNED
                  AND Occurred_At__c >= :f.Generated_At__c AND Occurred_At__c <= :endDt
                  AND Intake__r.Source__c = :f.Source__c
            ];
            Integer predicted = f.Projected_Signed__c == null ? 0 : f.Projected_Signed__c.intValue();
            Decimal denom = actual == 0 ? 1 : actual;
            f.Actual_Signed__c = actual;
            f.Error_Pct__c = (Math.abs(predicted - actual) / denom * 100).setScale(2);
            toUpdate.add(f);
        }
        if (!toUpdate.isEmpty()) update toUpdate;
    }
}