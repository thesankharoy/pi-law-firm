public with sharing class CallCenterDashboardController {

    public class DashboardData {
        @AuraEnabled public Integer totalAnswered;
        @AuraEnabled public Integer answeredWithinSix;
        @AuraEnabled public Decimal serviceLevel;
        @AuraEnabled public Decimal avgAnswerTime;
        @AuraEnabled public Decimal avgCallDuration;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {

        DashboardData data = new DashboardData();

        List<Task> calls = [
            SELECT Id,
                   CallDisposition,
                   CallDurationInSeconds,
                   Answer_Time_Seconds__c,
                   Call_SID__c
            FROM Task
            WHERE CallDisposition = 'Answered'
        ];

        Integer totalAnswered = 0;
        Integer withinSix = 0;

        Decimal totalAnswerTime = 0;
        Decimal totalCallDuration = 0;

        for(Task t : calls){

            totalAnswered++;

            if(t.Answer_Time_Seconds__c != null){

                totalAnswerTime += t.Answer_Time_Seconds__c;

                if(t.Answer_Time_Seconds__c <= 6){
                    withinSix++;
                }
            }

            if(t.CallDurationInSeconds != null){
                totalCallDuration += t.CallDurationInSeconds;
            }
        }

        data.totalAnswered = totalAnswered;
        data.answeredWithinSix = withinSix;

        data.serviceLevel =
            totalAnswered > 0
            ? (Decimal.valueOf(withinSix) * 100) / totalAnswered
            : 0;

        data.avgAnswerTime =
            totalAnswered > 0
            ? totalAnswerTime / totalAnswered
            : 0;

        data.avgCallDuration =
            totalAnswered > 0
            ? totalCallDuration / totalAnswered
            : 0;

        return data;
    }
}