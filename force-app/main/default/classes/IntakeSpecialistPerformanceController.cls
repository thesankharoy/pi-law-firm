public with sharing class IntakeSpecialistPerformanceController {

    public class SpecialistDTO {

        @AuraEnabled
        public String specialistName;

        @AuraEnabled
        public Integer totalIntakes;

        @AuraEnabled
        public Integer signedClients;

        @AuraEnabled
        public Decimal conversionRate;
    }

    @AuraEnabled(cacheable=true)
    public static List<SpecialistDTO> getPerformanceData() {

        List<SpecialistDTO> results =
            new List<SpecialistDTO>();

        AggregateResult[] totals = [

            SELECT Owner.Name name,
                   COUNT(Id) total

            FROM Intake__c

            GROUP BY Owner.Name
        ];

        Map<String,Integer> totalMap =
            new Map<String,Integer>();

        for(AggregateResult ar : totals){

            totalMap.put(
                (String)ar.get('name'),
                (Integer)ar.get('total')
            );
        }

        AggregateResult[] signed = [

            SELECT Owner.Name name,
                   COUNT(Id) total

            FROM Intake__c

            WHERE Status__c =
                'Retainer Agreement Signed'

            GROUP BY Owner.Name
        ];

        Map<String,Integer> signedMap =
            new Map<String,Integer>();

        for(AggregateResult ar : signed){

            signedMap.put(
                (String)ar.get('name'),
                (Integer)ar.get('total')
            );
        }

        for(String name : totalMap.keySet()){

            SpecialistDTO row =
                new SpecialistDTO();

            Integer total =
                totalMap.get(name);

            Integer signedCount =
                signedMap.containsKey(name)
                ? signedMap.get(name)
                : 0;

            row.specialistName = name;

            row.totalIntakes = total;

            row.signedClients = signedCount;

            row.conversionRate =
                total > 0
                ? ((Decimal)signedCount / total) * 100
                : 0;

            results.add(row);
        }

        return results;
    }
}