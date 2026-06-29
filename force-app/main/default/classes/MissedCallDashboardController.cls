public with sharing class MissedCallDashboardController {

    public class DashboardData {
        @AuraEnabled public Integer missedCalls;
        @AuraEnabled public Decimal missedPercentage;
        @AuraEnabled public Integer totalCalls;
        @AuraEnabled public List<Task> missedCallList;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData(String filterType) {

        Datetime startDate;

        if(filterType == 'TODAY'){
            startDate = Datetime.newInstance(
                Date.today(),
                Time.newInstance(0,0,0,0)
            );
        }
        else if(filterType == 'LAST7'){
            startDate = System.now().addDays(-7);
        }
        else{
            startDate = Datetime.newInstance(
                Date.today().toStartOfMonth(),
                Time.newInstance(0,0,0,0)
            );
        }

        List<Task> tasks = [
            SELECT Id,
                   Subject,
                   CallDisposition,
                   CallType,
                   CallDurationInSeconds,
                   Incoming_Time__c,
                   Owner.Name
            FROM Task
            WHERE CallType = 'Inbound'
            AND Incoming_Time__c >= :startDate
            ORDER BY Incoming_Time__c DESC
            LIMIT 5000
        ];

        Integer totalCalls = tasks.size();
        Integer missedCalls = 0;

        List<Task> missedList = new List<Task>();

        for(Task t : tasks){

            if(t.CallDisposition == 'Missed'){
                missedCalls++;

                if(missedList.size() < 100){
                    missedList.add(t);
                }
            }
        }

        Decimal missedPercent = 0;

        if(totalCalls > 0){
            missedPercent =
                ((Decimal)missedCalls * 100) / totalCalls;
            missedPercent = missedPercent.setScale(2);
        }

        DashboardData data = new DashboardData();
        data.totalCalls = totalCalls;
        data.missedCalls = missedCalls;
        data.missedPercentage = missedPercent;
        data.missedCallList = missedList;

        return data;
    }
}