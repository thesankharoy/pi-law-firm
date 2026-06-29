public with sharing class ResponseTimeConversionController {

    public class BucketData {
        @AuraEnabled public String bucket;
        @AuraEnabled public Integer calls;
        @AuraEnabled public Integer converted;
        @AuraEnabled public Decimal conversionRate;
        @AuraEnabled public Decimal totalCallPercent;
        @AuraEnabled public String barStyle;
    }

    public class DashboardData {
        @AuraEnabled public Decimal avgAnswerTime;
        @AuraEnabled public Integer totalCalls;
        @AuraEnabled public Decimal conversionRate;
        @AuraEnabled public Decimal missedCallRate;
        @AuraEnabled public List<BucketData> buckets;
        @AuraEnabled public List<String> insights;
        @AuraEnabled public String recommendation;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {

        DashboardData dto = new DashboardData();
        dto.buckets = new List<BucketData>();
        dto.insights = new List<String>();

        List<Task> tasks = [
            SELECT Id,
                   WhatId,
                   CallDisposition,
                   Answer_Time_Seconds__c
            FROM Task
            WHERE CallType = 'Inbound'
            AND Status = 'Completed'
        ];

        Set<Id> intakeIds = new Set<Id>();

        for(Task t : tasks){
            if(t.WhatId != null){
                intakeIds.add(t.WhatId);
            }
        }

        Map<Id, Intake__c> intakeMap =
            new Map<Id, Intake__c>(
                [
                    SELECT Id, Status__c
                    FROM Intake__c
                    WHERE Id IN :intakeIds
                ]
            );

        Map<String, BucketData> bucketMap =
            new Map<String, BucketData>();

        List<String> bucketOrder = new List<String>{
            '0-10 sec',
            '11-20 sec',
            '21-30 sec',
            '31-40 sec',
            '41-50 sec',
            '51-60 sec',
            '1-5 min',
            '5-15 min',
            '15-60 min',
            '>1 hour'
        };

        Integer totalCalls = 0;
        Integer convertedCalls = 0;
        Integer missedCalls = 0;
        Decimal totalAnswerTime = 0;

        for(Task t : tasks){

            totalCalls++;

            if(t.Answer_Time_Seconds__c == null){
                missedCalls++;
                continue;
            }

            totalAnswerTime += t.Answer_Time_Seconds__c;

            String bucket = getBucket(
                Integer.valueOf(t.Answer_Time_Seconds__c)
            );

            if(!bucketMap.containsKey(bucket)){
                BucketData b = new BucketData();
                b.bucket = bucket;
                b.calls = 0;
                b.converted = 0;
                bucketMap.put(bucket,b);
            }

            bucketMap.get(bucket).calls++;

            Intake__c intake =
                intakeMap.get(t.WhatId);

            if(intake != null &&
               intake.Status__c == 'Converted'){

                bucketMap.get(bucket).converted++;
                convertedCalls++;
            }
        }

        for(String bucket : bucketOrder){

            if(bucketMap.containsKey(bucket)){

                BucketData row =
                    bucketMap.get(bucket);

                row.conversionRate =
                    row.calls > 0
                    ? (Decimal.valueOf(row.converted) /
                       row.calls) * 100
                    : 0;

                row.totalCallPercent =
                    totalCalls > 0
                    ? (Decimal.valueOf(row.calls) /
                       totalCalls) * 100
                    : 0;

                   row.barStyle = 'width:' +
                   Math.min(
                       100,
                       Integer.valueOf(
                           row.conversionRate
                       )
                   ) +
                   '%';

                dto.buckets.add(row);
            }
        }

        dto.totalCalls = totalCalls;

        dto.avgAnswerTime =
            totalCalls > 0
            ? totalAnswerTime / totalCalls
            : 0;

        dto.conversionRate =
            totalCalls > 0
            ? (Decimal.valueOf(convertedCalls)
               / totalCalls) * 100
            : 0;

        dto.missedCallRate =
            totalCalls > 0
            ? (Decimal.valueOf(missedCalls)
               / totalCalls) * 100
            : 0;

        dto.insights.add(
            'Calls answered within 20 seconds generally produce the highest conversion rates.'
        );

        dto.insights.add(
            'Conversion rates decrease as answer times increase.'
        );

        dto.insights.add(
            'Average answer time is '
            + dto.avgAnswerTime.setScale(0)
            + ' seconds.'
        );

        dto.recommendation =
            'Aim to answer 80% of incoming calls within 20 seconds to maximize conversions.';

        return dto;
    }

    private static String getBucket(Integer secs){

        if(secs <= 10) return '0-10 sec';
        if(secs <= 20) return '11-20 sec';
        if(secs <= 30) return '21-30 sec';
        if(secs <= 40) return '31-40 sec';
        if(secs <= 50) return '41-50 sec';
        if(secs <= 60) return '51-60 sec';
        if(secs <= 300) return '1-5 min';
        if(secs <= 900) return '5-15 min';
        if(secs <= 3600) return '15-60 min';

        return '>1 hour';
    }
}