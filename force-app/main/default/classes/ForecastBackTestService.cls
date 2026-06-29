/**
 * Back-test (US70-7): for each forecast whose window has closed and has no accuracy record yet,
 * counts the actual signings that occurred in the window (from Stage_Transition__c) and writes a
 * Forecast_Accuracy__c with predicted, actual, and absolute error %. Deterministic, no callout.
 */
public with sharing class ForecastBackTestService {

    public static void run() {
        Set<Id> alreadyTested = new Set<Id>();
        for (Forecast_Accuracy__c a : [SELECT Forecast__c FROM Forecast_Accuracy__c WHERE Forecast__c != null]) {
            alreadyTested.add(a.Forecast__c);
        }

        List<Conversion_Forecast__c> due = [
            SELECT Id, Period_Start__c, Period_End__c, Projected_Signed__c
            FROM Conversion_Forecast__c
            WHERE Period_End__c < TODAY AND Id NOT IN :alreadyTested
        ];
        if (due.isEmpty()) return;

        List<Forecast_Accuracy__c> rows = new List<Forecast_Accuracy__c>();
        for (Conversion_Forecast__c f : due) {
            DateTime startDt = DateTime.newInstance(f.Period_Start__c, Time.newInstance(0, 0, 0, 0));
            DateTime endDt = DateTime.newInstance(f.Period_End__c, Time.newInstance(23, 59, 59, 0));
            Integer actual = [
                SELECT COUNT()
                FROM Stage_Transition__c
                WHERE To_Status__c IN :ConversionRateService.SIGNED
                  AND Occurred_At__c >= :startDt AND Occurred_At__c <= :endDt
            ];
            Integer predicted = f.Projected_Signed__c == null ? 0 : f.Projected_Signed__c.intValue();
            Decimal denom = actual == 0 ? 1 : actual;
            Decimal errPct = (Math.abs(predicted - actual) / denom * 100).setScale(2);
            rows.add(new Forecast_Accuracy__c(
                Forecast__c = f.Id, Predicted__c = predicted, Actual__c = actual, Error_Pct__c = errPct));
        }
        insert rows;
    }
}