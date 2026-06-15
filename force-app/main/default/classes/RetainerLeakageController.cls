public with sharing class RetainerLeakageController {

    public class LeakageDTO {

        @AuraEnabled
        public Integer sentCount;

        @AuraEnabled
        public Integer signedCount;

        @AuraEnabled
        public Integer unsignedCount;

        @AuraEnabled
        public Decimal leakageRate;
    }

    @AuraEnabled(cacheable=true)
    public static LeakageDTO getLeakageData() {

        LeakageDTO dto =
            new LeakageDTO();

        dto.sentCount = [

            SELECT COUNT()

            FROM Intake__c

            WHERE Retainer_Agreement_Sent_Entered_At__c != NULL

        ];

        dto.signedCount = [

            SELECT COUNT()

            FROM Intake__c

            WHERE Retainer_Agreement_Signed_Entered_At__c != NULL

        ];

        dto.unsignedCount =
            dto.sentCount -
            dto.signedCount;

        dto.leakageRate =

            dto.sentCount > 0

            ?

            ((Decimal)dto.unsignedCount /
             dto.sentCount) * 100

            : 0;

        return dto;
    }
}