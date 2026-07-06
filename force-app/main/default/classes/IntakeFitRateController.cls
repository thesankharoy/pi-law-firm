public with sharing class IntakeFitRateController {

    private static final Set<String> QUALITY_TIERS = new Set<String>{ 'Hot', 'Warm' };

    public class FitRateDTO {
        @AuraEnabled public String source;
        @AuraEnabled public Integer totalIntakes;
        @AuraEnabled public Integer hotIntakes;
        @AuraEnabled public Integer warmIntakes;
        @AuraEnabled public Integer coldIntakes;
      //  @AuraEnabled public Integer qualifiedIntakes;   // Hot + Warm
        @AuraEnabled public Decimal qualityRate;        // qualified / total * 100
    }

    @AuraEnabled(cacheable=true)
    public static List<FitRateDTO> getFitRateBySource() {

        Map<String, Integer> totalMap = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Source__c source, COUNT(Id) c
            FROM Intake__c
            WHERE Source__c != NULL
            GROUP BY Source__c
        ]) {
            totalMap.put(String.valueOf(ar.get('source')), (Integer) ar.get('c'));
        }

        Map<String, Integer> hotMap  = countByTier('Hot');
        Map<String, Integer> warmMap = countByTier('Warm');
        Map<String, Integer> coldMap = countByTier('Cold');   // Cold queried directly

        List<FitRateDTO> results = new List<FitRateDTO>();
        for (String source : totalMap.keySet()) {
            Integer total = totalMap.get(source);
            Integer hot   = hotMap.containsKey(source)  ? hotMap.get(source)  : 0;
            Integer warm  = warmMap.containsKey(source) ? warmMap.get(source) : 0;
            Integer cold  = coldMap.containsKey(source) ? coldMap.get(source) : 0;
            //Integer qualified = hot + warm;

            FitRateDTO row = new FitRateDTO();
            row.source           = source;
            row.totalIntakes     = total;
            row.hotIntakes       = hot;
            row.warmIntakes      = warm;
            row.coldIntakes      = cold;
           // weights per tier
            Decimal weightedSum = (hot * 100) + (warm * 50) + (cold * 0);
            
            row.qualityRate = total > 0
                ? (weightedSum / total).setScale(1, System.RoundingMode.HALF_UP)
                : 0;

            results.add(row);
        }

        results.sort(new FitRateComparator());
        return results;
    }

    private static Map<String, Integer> countByTier(String tier) {
        Map<String, Integer> m = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Source__c source, COUNT(Id) c
            FROM Intake__c
            WHERE Source__c != NULL
            AND Case_Quality_Derived__c = :tier
            GROUP BY Source__c
        ]) {
            m.put(String.valueOf(ar.get('source')), (Integer) ar.get('c'));
        }
        return m;
    }

    public class FitRateComparator implements Comparator<FitRateDTO> {
        public Integer compare(FitRateDTO a, FitRateDTO b) {
            if (a.qualityRate > b.qualityRate) return -1;
            if (a.qualityRate < b.qualityRate) return 1;
            return 0;
        }
    }
}