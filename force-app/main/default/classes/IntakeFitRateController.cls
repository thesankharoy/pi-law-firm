public with sharing class IntakeFitRateController {

    public class FitRateDTO {

        @AuraEnabled
        public String source;

        @AuraEnabled
        public Integer totalIntakes;

        @AuraEnabled
        public Integer hotIntakes;

        @AuraEnabled
        public Decimal qualityRate;
    }

    @AuraEnabled(cacheable=true)
    public static List<FitRateDTO> getFitRateBySource() {

        Map<String, Integer> totalMap = new Map<String, Integer>();
        Map<String, Integer> hotMap = new Map<String, Integer>();

        // Total Intakes by Source
        for (AggregateResult ar : [

            SELECT Source__c source,
                   COUNT(Id) total

            FROM Intake__c

            WHERE Source__c != NULL

            GROUP BY Source__c

        ]) {

            totalMap.put(
                String.valueOf(ar.get('source')),
                (Integer) ar.get('total')
            );
        }

        // Hot Intakes by Source
        for (AggregateResult ar : [

            SELECT Source__c source,
                   COUNT(Id) total

            FROM Intake__c

            WHERE Source__c != NULL
            AND Case_Quality_Derived__c = 'Hot'

            GROUP BY Source__c

        ]) {

            hotMap.put(
                String.valueOf(ar.get('source')),
                (Integer) ar.get('total')
            );
        }

        List<FitRateDTO> results = new List<FitRateDTO>();

        for (String source : totalMap.keySet()) {

            Integer total = totalMap.get(source);

            Integer hot =
                hotMap.containsKey(source)
                ? hotMap.get(source)
                : 0;

            FitRateDTO row = new FitRateDTO();

            row.source = source;
            row.totalIntakes = total;
            row.hotIntakes = hot;

            row.qualityRate =
                total > 0
                ? (((Decimal) hot / total) * 100)
                : 0;

            results.add(row);
        }

        results.sort(new FitRateComparator());

        return results;
    }

    public class FitRateComparator
        implements Comparator<FitRateDTO> {

        public Integer compare(
            FitRateDTO a,
            FitRateDTO b
        ) {
            if (a.qualityRate > b.qualityRate) {
                return -1;
            }

            if (a.qualityRate < b.qualityRate) {
                return 1;
            }

            return 0;
        }
    }
}