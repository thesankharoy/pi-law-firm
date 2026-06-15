public with sharing class ResponseTimeConversionController {

    public class ResponseConversionDTO {

        @AuraEnabled
        public String bucket;

        @AuraEnabled
        public Integer totalIntakes;

        @AuraEnabled
        public Integer convertedIntakes;

        @AuraEnabled
        public Decimal conversionRate;

        @AuraEnabled
        public Decimal percentage;
    }

    @AuraEnabled(cacheable=true)
    public static List<ResponseConversionDTO>
    getResponseTimeVsConversion() {

        Map<String,Integer> totalMap =
            new Map<String,Integer>();

        Map<String,Integer> convertedMap =
            new Map<String,Integer>();

        List<String> buckets = new List<String>{
            'Under 5 Min',
            '5-15 Min',
            '15-30 Min',
            '30-60 Min',
            '1-4 Hours',
            '4+ Hours'
        };

        for(String bucket : buckets){

            totalMap.put(bucket,0);
            convertedMap.put(bucket,0);
        }

        for(Intake__c intake : [

            SELECT
                CreatedDate,
                First_Response_DateTime__c,
                Status__c

            FROM Intake__c

            WHERE First_Response_DateTime__c != NULL
        ]){

            Long diffMs =
                intake.First_Response_DateTime__c.getTime()
                - intake.CreatedDate.getTime();

            Decimal minutes =
                diffMs / (1000.0 * 60);

            String bucket;

            if(minutes < 5){

                bucket = 'Under 5 Min';

            }else if(minutes < 15){

                bucket = '5-15 Min';

            }else if(minutes < 30){

                bucket = '15-30 Min';

            }else if(minutes < 60){

                bucket = '30-60 Min';

            }else if(minutes < 240){

                bucket = '1-4 Hours';

            }else{

                bucket = '4+ Hours';
            }

            totalMap.put(
                bucket,
                totalMap.get(bucket) + 1
            );

            if(intake.Status__c == 'Converted'){

                convertedMap.put(
                    bucket,
                    convertedMap.get(bucket) + 1
                );
            }
        }

        Integer maxRate = 0;

        List<ResponseConversionDTO> results =
            new List<ResponseConversionDTO>();

        for(String bucket : buckets){

            Integer total =
                totalMap.get(bucket);

            Integer converted =
                convertedMap.get(bucket);

            Decimal rate = 0;

            if(total > 0){

                rate =
                    ((Decimal)converted /
                    total) * 100;
            }

            if(rate > maxRate){

                maxRate =
                    Integer.valueOf(
                        Math.round(rate)
                    );
            }

            ResponseConversionDTO row =
                new ResponseConversionDTO();

            row.bucket = bucket;
            row.totalIntakes = total;
            row.convertedIntakes = converted;
            row.conversionRate =
                rate.setScale(1);

            results.add(row);
        }

        for(ResponseConversionDTO row : results){

            row.percentage =
                maxRate > 0
                ? (row.conversionRate /
                    maxRate) * 100
                : 0;
        }

        return results;
    }
}