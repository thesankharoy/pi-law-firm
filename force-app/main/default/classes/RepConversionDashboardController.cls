public with sharing class RepConversionDashboardController {

    public class RepDTO {

        @AuraEnabled
        public String repName;

        @AuraEnabled
        public Integer totalIntakes;

        @AuraEnabled
        public Integer convertedIntakes;

        @AuraEnabled
        public Decimal conversionRate;
    }

    @AuraEnabled(cacheable=true)
    public static List<RepDTO> getRepConversionData() {

        Map<Id, RepDTO> repMap =
            new Map<Id, RepDTO>();
         

        // Total Intakes by Specialist
        for (AggregateResult ar : [

            SELECT OwnerId,
                   Owner.Name ownerName,
                   COUNT(Id) totalCount

            FROM Intake__c

            GROUP BY OwnerId,
                     Owner.Name

        ]) {

            RepDTO row = new RepDTO();

            row.repName =
                (String) ar.get('ownerName');

            row.totalIntakes =
                (Integer) ar.get('totalCount');

            row.convertedIntakes = 0;

            row.conversionRate = 0;

            repMap.put(
                (Id) ar.get('OwnerId'),
                row
            );
        }

        // Converted Intakes by Specialist
        for (AggregateResult ar : [

            SELECT OwnerId,
                   COUNT(Id) convertedCount

            FROM Intake__c

            WHERE Status__c = 'Converted'

            GROUP BY OwnerId

        ]) {

            Id ownerId =
                (Id) ar.get('OwnerId');

            if(repMap.containsKey(ownerId)) {

                repMap.get(ownerId)
                    .convertedIntakes =
                        (Integer) ar.get('convertedCount');
            }
        }

        // Calculate Conversion Rate
        List<RepDTO> results =
            new List<RepDTO>();

        for(RepDTO row : repMap.values()) {

            if(row.totalIntakes > 0) {

                row.conversionRate =
                    ((Decimal) row.convertedIntakes
                    / row.totalIntakes) * 100;
            }

            results.add(row);
        }

        // Sort Highest Conversion First
        results.sort(new ConversionComparator());

        return results;
    }

    public class ConversionComparator
        implements Comparator<RepDTO> {

        public Integer compare(
            RepDTO a,
            RepDTO b
        ) {

            if(a.conversionRate >
               b.conversionRate) {

                return -1;
            }

            if(a.conversionRate <
               b.conversionRate) {

                return 1;
            }

            return 0;
        }
    }
}