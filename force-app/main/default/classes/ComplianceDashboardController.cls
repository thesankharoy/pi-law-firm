public with sharing class ComplianceDashboardController {

    public class DashboardData {
        @AuraEnabled public Integer totalCalls;
        @AuraEnabled public Integer flaggedCalls;
        @AuraEnabled public Decimal avgRiskScore;
        @AuraEnabled public Map<String,Integer> riskLevels;
        @AuraEnabled public Map<String,Integer> issueTypes;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {

        DashboardData data = new DashboardData();

        List<Task> tasks = [
            SELECT Id,
                   Compliance_Risk_Flag__c,
                   Compliance_Risk_Score__c,
                   Compliance_Risk_Level__c,
                   Compliance_Issue_Type__c
            FROM Task
            WHERE Status='Completed'
        ];

        data.totalCalls = tasks.size();

        Integer flagged = 0;
        Decimal totalScore = 0;

        data.riskLevels = new Map<String,Integer>();
        data.issueTypes = new Map<String,Integer>();

        for(Task t : tasks){

            if(t.Compliance_Risk_Flag__c){
                flagged++;
            }

            if(t.Compliance_Risk_Score__c != null){
                totalScore += t.Compliance_Risk_Score__c;
            }

            String level = String.isBlank(t.Compliance_Risk_Level__c)
                ? 'None'
                : t.Compliance_Risk_Level__c;

            data.riskLevels.put(
                level,
                (data.riskLevels.containsKey(level)
                    ? data.riskLevels.get(level)
                    : 0) + 1
            );

            if(!String.isBlank(t.Compliance_Issue_Type__c)){

                List<String> issues =
                    t.Compliance_Issue_Type__c.split(';');

                for(String issue : issues){

                    issue = issue.trim();

                    if(String.isBlank(issue)){
                        continue;
                    }

                    data.issueTypes.put(
                        issue,
                        (data.issueTypes.containsKey(issue)
                            ? data.issueTypes.get(issue)
                            : 0) + 1
                    );
                }
            }
        }

        data.flaggedCalls = flagged;

        data.avgRiskScore =
            tasks.isEmpty()
            ? 0
            : totalScore / tasks.size();

        return data;
    }
}