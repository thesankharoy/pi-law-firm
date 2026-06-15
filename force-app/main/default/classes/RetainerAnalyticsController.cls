public with sharing class RetainerAnalyticsController {

    public class RetainerAnalyticsDTO {
        @AuraEnabled public Integer sentCount;
        @AuraEnabled public Integer openCount;
        @AuraEnabled public Integer signedCount;
        @AuraEnabled public Decimal conversionRate;
        @AuraEnabled public Decimal avgDaysToSign;
    }

    @AuraEnabled(cacheable=true)
    public static RetainerAnalyticsDTO getAnalytics() {

        RetainerAnalyticsDTO dto = new RetainerAnalyticsDTO();

        // ✅ Correct COUNT queries
        dto.sentCount = (Integer)[
            SELECT COUNT()
            FROM Intake__c
            WHERE Status__c = 'Retainer Agreement Sent'
        ];

        dto.openCount = (Integer)[
            SELECT COUNT()
            FROM Intake__c
            WHERE Status__c = 'Open'
        ];

        dto.signedCount = (Integer)[
            SELECT COUNT()
            FROM Intake__c
            WHERE Status__c = 'Retainer Agreement Signed'
        ];

        // Conversion rate
        dto.conversionRate = (dto.sentCount > 0)
            ? (Decimal.valueOf(dto.signedCount) / Decimal.valueOf(dto.sentCount)) * 100
            : 0;

        // ✅ FIX: Only signed records + proper fields
        List<Intake__c> signedIntakes = [
            SELECT Retainer_Agreement_Sent_Entered_At__c,
                   Retainer_Agreement_Signed_Entered_At__c
            FROM Intake__c
            WHERE Status__c = 'Retainer Agreement Signed'
            AND Retainer_Agreement_Sent_Entered_At__c != null
            AND Retainer_Agreement_Signed_Entered_At__c != null
        ];

        Decimal totalDays = 0;

        for (Intake__c i : signedIntakes) {

            Long diffMs =
                i.Retainer_Agreement_Signed_Entered_At__c.getTime()
                - i.Retainer_Agreement_Sent_Entered_At__c.getTime();

            Decimal days = diffMs / (1000 * 60 * 60 * 24);

            totalDays += days;
        }

        dto.avgDaysToSign = (signedIntakes.size() > 0)
            ? totalDays / signedIntakes.size()
            : 0;

        return dto;
    }
}