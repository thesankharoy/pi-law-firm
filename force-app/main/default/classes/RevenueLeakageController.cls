public with sharing class RevenueLeakageController {

    public class LeakageRow {

        @AuraEnabled public String stageName;
        @AuraEnabled public Integer count;
        @AuraEnabled public Integer dropOff;
        @AuraEnabled public Decimal dropOffPercent;
    }

 @AuraEnabled(cacheable=true)
public static List<LeakageRow> getLeakageData() {

    // Dynamic Status__c picklist values
    List<String> stages = new List<String>();

    Schema.DescribeFieldResult statusDescribe =
        Intake__c.Status__c.getDescribe();

    for (Schema.PicklistEntry entry : statusDescribe.getPicklistValues()) {
        if (entry.isActive()) {
            stages.add(entry.getValue());
        }
    }

    Map<String,Integer> counts = new Map<String,Integer>();

    for (AggregateResult ar : [
        SELECT Status__c status,
               COUNT(Id) total
        FROM Intake__c
        GROUP BY Status__c
    ]){
        counts.put(
            (String)ar.get('status'),
            (Integer)ar.get('total')
        );
    }

    List<LeakageRow> results = new List<LeakageRow>();

    for(Integer i = 0; i < stages.size() - 1; i++){

        Integer currentCount =
            counts.containsKey(stages[i])
            ? counts.get(stages[i])
            : 0;

        Integer nextCount =
            counts.containsKey(stages[i + 1])
            ? counts.get(stages[i + 1])
            : 0;

        LeakageRow row = new LeakageRow();

        row.stageName = stages[i];
        row.count = currentCount;
        row.dropOff = currentCount - nextCount;

        if(currentCount > 0){
            row.dropOffPercent =
                ((Decimal)(currentCount - nextCount)
                / currentCount) * 100;
        }else{
            row.dropOffPercent = 0;
        }

        results.add(row);
    }

    return results;
}
}