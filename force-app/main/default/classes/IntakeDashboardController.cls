public with sharing class IntakeDashboardController {

   @AuraEnabled(cacheable=true)
public static Integer getTotalLeadsEntered(
    Integer monthNumber,
    Integer yearNumber,
    String dateFilter
) {

    // Date Filter takes priority
    if(String.isNotBlank(dateFilter) && dateFilter != 'ALL') {

        if(dateFilter == 'TODAY')
            return [SELECT COUNT() FROM Intake__c WHERE CreatedDate = TODAY];

        if(dateFilter == 'YESTERDAY')
            return [SELECT COUNT() FROM Intake__c WHERE CreatedDate = YESTERDAY];

        if(dateFilter == 'THIS_WEEK')
            return [SELECT COUNT() FROM Intake__c WHERE CreatedDate = THIS_WEEK];

        if(dateFilter == 'LAST_WEEK')
            return [SELECT COUNT() FROM Intake__c WHERE CreatedDate = LAST_WEEK];

        if(dateFilter == 'THIS_MONTH')
            return [SELECT COUNT() FROM Intake__c WHERE CreatedDate = THIS_MONTH];

        if(dateFilter == 'LAST_MONTH')
            return [SELECT COUNT() FROM Intake__c WHERE CreatedDate = LAST_MONTH];

        if(dateFilter == 'THIS_YEAR')
            return [SELECT COUNT() FROM Intake__c WHERE CreatedDate = THIS_YEAR];

        if(dateFilter == 'LAST_YEAR')
            return [SELECT COUNT() FROM Intake__c WHERE CreatedDate = LAST_YEAR];
    }

    // Month Filter
    if(monthNumber != null && monthNumber > 0) {

        Date startDate = Date.newInstance(yearNumber, monthNumber, 1);
        Date endDate = startDate.addMonths(1);

        return [
            SELECT COUNT()
            FROM Intake__c
            WHERE CreatedDate >= :DateTime.newInstance(startDate, Time.newInstance(0,0,0,0))
            AND CreatedDate < :DateTime.newInstance(endDate, Time.newInstance(0,0,0,0))
        ];
    }

    return [SELECT COUNT() FROM Intake__c];
}
  @AuraEnabled(cacheable=true)
public static Integer getSignedClients(
    Integer monthNumber,
    Integer yearNumber,
    String dateFilter
) {

    if(String.isNotBlank(dateFilter) && dateFilter != 'ALL') {

        if(dateFilter == 'TODAY')
            return [SELECT COUNT() FROM Intake__c
                    WHERE Status__c='Retainer Agreement Signed'
                    AND CreatedDate = TODAY];

        if(dateFilter == 'THIS_MONTH')
            return [SELECT COUNT() FROM Intake__c
                    WHERE Status__c='Retainer Agreement Signed'
                    AND CreatedDate = THIS_MONTH];

        if(dateFilter == 'LAST_MONTH')
            return [SELECT COUNT() FROM Intake__c
                    WHERE Status__c='Retainer Agreement Signed'
                    AND CreatedDate = LAST_MONTH];

        if(dateFilter == 'THIS_YEAR')
            return [SELECT COUNT() FROM Intake__c
                    WHERE Status__c='Retainer Agreement Signed'
                    AND CreatedDate = THIS_YEAR];

        if(dateFilter == 'LAST_YEAR')
            return [SELECT COUNT() FROM Intake__c
                    WHERE Status__c='Retainer Agreement Signed'
                    AND CreatedDate = LAST_YEAR];
    }

    if(monthNumber != null && monthNumber > 0) {

        Date startDate = Date.newInstance(yearNumber, monthNumber, 1);
        Date endDate = startDate.addMonths(1);

        return [
            SELECT COUNT()
            FROM Intake__c
            WHERE Status__c='Retainer Agreement Signed'
            AND CreatedDate >= :DateTime.newInstance(startDate, Time.newInstance(0,0,0,0))
            AND CreatedDate < :DateTime.newInstance(endDate, Time.newInstance(0,0,0,0))
        ];
    }

    return [
        SELECT COUNT()
        FROM Intake__c
        WHERE Status__c='Retainer Agreement Signed'
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

    if (totalIntakes == 0) {
        return 0;
    }

    return ((Decimal)convertedIntakes / totalIntakes) * 100;
}
   @AuraEnabled(cacheable=true)
public static List<ResponseTimeWrapper> getResponseTimeData() {

    List<ResponseTimeWrapper> results = new List<ResponseTimeWrapper>();

    Decimal maxTime = 0;

    List<AggregateResult> queryResults = [

        SELECT
            Source__c source,
            AVG(Response_Time_Minutes__c) avgTime

        FROM Intake__c

        WHERE Response_Time_Minutes__c != NULL
        AND Response_Time_Minutes__c >= 0

        GROUP BY Source__c
    ];

    for (AggregateResult ar : queryResults) {

        Decimal avgTime = (Decimal) ar.get('avgTime');

        if (avgTime > maxTime) {
            maxTime = avgTime;
        }
    }

    for (AggregateResult ar : queryResults) {

        ResponseTimeWrapper row = new ResponseTimeWrapper();

        row.source = (String) ar.get('source');

        row.avgResponseTime =
            (Decimal) ar.get('avgTime');

        if (row.avgResponseTime < 0) {
            row.avgResponseTime = 0;
        }

        row.percentage =
            maxTime > 0
            ? ((maxTime - row.avgResponseTime) / maxTime) * 100
            : 100;

        results.add(row);
    }

    results.sort(new ResponseTimeSorter());

    return results;
}

public class ResponseTimeWrapper {

    @AuraEnabled
    public String source;

    @AuraEnabled
    public Decimal avgResponseTime;

    @AuraEnabled
    public Decimal percentage;
}

public class ResponseTimeSorter
implements Comparator<ResponseTimeWrapper> {

    public Integer compare(
        ResponseTimeWrapper a,
        ResponseTimeWrapper b
    ) {

        if (a.avgResponseTime > b.avgResponseTime) {
            return 1;
        }

        if (a.avgResponseTime < b.avgResponseTime) {
            return -1;
        }

        return 0;
    }
}
}