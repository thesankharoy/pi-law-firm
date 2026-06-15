public with sharing class IntakeAuditController {

    public class AuditSummaryDTO {

        @AuraEnabled public Integer statusChanges;
        @AuraEnabled public Integer ownerChanges;
        @AuraEnabled public Integer sourceChanges;
        @AuraEnabled public Integer totalEvents;
    }

    public class AuditRecordDTO {

        @AuraEnabled public String userName;
        @AuraEnabled public String fieldName;
        @AuraEnabled public String oldValue;
        @AuraEnabled public String newValue;
        @AuraEnabled public Datetime changeDate;
    }

    @AuraEnabled(cacheable=true)
    public static AuditSummaryDTO getAuditSummary() {

        AuditSummaryDTO dto =
            new AuditSummaryDTO();

        dto.statusChanges = [
            SELECT COUNT()
            FROM Intake__History
            WHERE Field = 'Status__c'
        ];

        dto.ownerChanges = [
            SELECT COUNT()
            FROM Intake__History
            WHERE Field = 'Owner'
        ];

        dto.sourceChanges = [
            SELECT COUNT()
            FROM Intake__History
            WHERE Field = 'Source__c'
        ];

        dto.totalEvents = [
            SELECT COUNT()
            FROM Intake__History
        ];

        return dto;
    }

    @AuraEnabled(cacheable=true)
    public static List<AuditRecordDTO> getRecentAuditRecords() {

        List<AuditRecordDTO> results =
            new List<AuditRecordDTO>();

        for(Intake__History history : [

            SELECT
                Field,
                OldValue,
                NewValue,
                CreatedDate,
                CreatedBy.Name

            FROM Intake__History

            ORDER BY CreatedDate DESC

            LIMIT 50
        ]){

            AuditRecordDTO row =
                new AuditRecordDTO();

            row.userName =
                history.CreatedBy.Name;

            row.fieldName =
                history.Field;

            row.oldValue =
                String.valueOf(
                    history.OldValue
                );

            row.newValue =
                String.valueOf(
                    history.NewValue
                );

            row.changeDate =
                history.CreatedDate;

            results.add(row);
        }

        return results;
    }
}