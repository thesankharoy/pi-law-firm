public with sharing class IntakeConversionController {

    public class ConversionDTO {

        @AuraEnabled
        public String source;

        @AuraEnabled
        public Integer totalIntakes;

        @AuraEnabled
        public Integer signedClients;

        @AuraEnabled
        public Decimal conversionRate;
    }

    @AuraEnabled(cacheable=true)
    public static List<ConversionDTO>
    getConversionBySource() {

        Map<String,Integer> totalMap =
            new Map<String,Integer>();

        Map<String,Integer> signedMap =
            new Map<String,Integer>();

        for(AggregateResult ar : [

            SELECT Source__c source,
                   COUNT(Id) total

            FROM Intake__c

            WHERE Source__c != NULL

            GROUP BY Source__c

        ]){

            totalMap.put(
                String.valueOf(ar.get('source')),
                (Integer)ar.get('total')
            );
        }

        for(AggregateResult ar : [

            SELECT Source__c source,
                   COUNT(Id) total

            FROM Intake__c

            WHERE Status__c =
                'Retainer Agreement Signed'

            AND Source__c != NULL

            GROUP BY Source__c

        ]){

            signedMap.put(
                String.valueOf(ar.get('source')),
                (Integer)ar.get('total')
            );
        }

        List<ConversionDTO> results =
            new List<ConversionDTO>();

        for(String source :
            totalMap.keySet()){

            Integer total =
                totalMap.get(source);

            Integer signed =
                signedMap.containsKey(source)
                ? signedMap.get(source)
                : 0;

            ConversionDTO row =
                new ConversionDTO();

            row.source = source;
            row.totalIntakes = total;
            row.signedClients = signed;

            row.conversionRate =
                total > 0
                ? ((Decimal)signed / total) * 100
                : 0;

            results.add(row);
        }

        return results;
    }
}