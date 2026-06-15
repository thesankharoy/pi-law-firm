public with sharing class IntakeSourceDashboardController {

    @AuraEnabled(cacheable=true)
    public static List<SourcePerformanceWrapper> getSourcePerformance() {

        AggregateResult[] results = [
            SELECT Source__c source,
                   COUNT(Id) totalIntakes
            FROM Intake__c
            WHERE Source__c != null
            GROUP BY Source__c
            ORDER BY COUNT(Id) DESC
        ];

        List<SourcePerformanceWrapper> output = new List<SourcePerformanceWrapper>();

        for (AggregateResult ar : results) {
            output.add(new SourcePerformanceWrapper(
                (String) ar.get('source'),
                (Integer) ar.get('totalIntakes')
            ));
        }

        return output;
    }

    public class SourcePerformanceWrapper {
        @AuraEnabled public String source;
        @AuraEnabled public Integer totalIntakes;

        public SourcePerformanceWrapper(String source, Integer totalIntakes) {
            this.source = source;
            this.totalIntakes = totalIntakes;
        }
    }
}