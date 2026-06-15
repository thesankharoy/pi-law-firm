public with sharing class IntakeDashboardController {

    @AuraEnabled(cacheable=true)
    public static Integer getTotalLeadsEntered() {

        return [
            SELECT COUNT()
            FROM Intake__c
        ];
    }
    @AuraEnabled(cacheable=true)
    public static Integer getSignedClients() {

    return [
        SELECT COUNT()
        FROM Intake__c
        WHERE Status__c = 'Retainer Agreement Signed'
    ];
}
    
 @AuraEnabled(cacheable=true)
public static Decimal getConversionRate() {

    Integer totalIntakes = [
        SELECT COUNT()
        FROM Intake__c
    ];

    Integer convertedIntakes = [
        SELECT COUNT()
        FROM Intake__c
        WHERE Status__c = 'Converted'
    ];

    if(totalIntakes == 0){
        return 0;
    }

    return ((Decimal)convertedIntakes / totalIntakes) * 100;
}
    
    //Next Intake Source
    public class ResponseTimeWrapper {

        @AuraEnabled
        public String source;

        @AuraEnabled
        public Decimal avgResponseTime;

        @AuraEnabled
        public Decimal percentage;
    }

    @AuraEnabled(cacheable=true)
    public static List<ResponseTimeWrapper> getResponseTimeData() {

        List<ResponseTimeWrapper> results =
            new List<ResponseTimeWrapper>();

        Decimal maxTime = 0;

        List<AggregateResult> queryResults = [

            SELECT Source__c source,
                   AVG(Response_Time_Minutes__c) avgTime

            FROM Intake__c

            WHERE Response_Time_Minutes__c != NULL

            GROUP BY Source__c
        ];

        for(AggregateResult ar : queryResults){

            Decimal avg =
                (Decimal)ar.get('avgTime');

            if(avg > maxTime){
                maxTime = avg;
            }
        }

        for(AggregateResult ar : queryResults){

            ResponseTimeWrapper row =
                new ResponseTimeWrapper();

            row.source =
                (String)ar.get('source');

            row.avgResponseTime =
                (Decimal)ar.get('avgTime');

            row.percentage =
                maxTime > 0
                ? (row.avgResponseTime/maxTime)*100
                : 0;

            results.add(row);
        }

        return results;
    }
}