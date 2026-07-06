public with sharing class IntakeAnalyticsController {

    @AuraEnabled(cacheable=true)
    public static IntakeResponse getIntakes(Integer pageSize, Integer pageNumber) {

        Integer offsetSize = (pageNumber - 1) * pageSize;

        // 1. All intake IDs that already have at least one task (followed up)
        Set<Id> intakesWithTask = new Set<Id>();
        for (AggregateResult ar : [
            SELECT WhatId wid
            FROM Task
            WHERE What.Type = 'Intake__c'
            AND WhatId != NULL
            GROUP BY WhatId
        ]) {
            intakesWithTask.add((Id) ar.get('wid'));
        }

        // 2. Un-followed Active_Intake IDs (record type + no task)
        List<Id> unfollowedIds = new List<Id>();
        for (Intake__c i : [
            SELECT Id
            FROM Intake__c
            WHERE RecordType.DeveloperName = 'Active_Intake'
            AND Id NOT IN :intakesWithTask
            ORDER BY CreatedDate DESC
        ]) {
            unfollowedIds.add(i.Id);
        }

        Integer totalRecords = unfollowedIds.size();

        // 3. Page over just those IDs
        List<IntakeWrapper> wrapped = new List<IntakeWrapper>();
        Integer endIndex = Math.min(offsetSize + pageSize, unfollowedIds.size());
        if (offsetSize < unfollowedIds.size()) {
            Set<Id> pageIds = new Set<Id>();
            for (Integer idx = offsetSize; idx < endIndex; idx++) {
                pageIds.add(unfollowedIds[idx]);
            }
            for (Intake__c i : [
                SELECT Id, Name, CreatedDate
                FROM Intake__c
                WHERE Id IN :pageIds
                ORDER BY CreatedDate DESC
            ]) {
                wrapped.add(new IntakeWrapper(i.Id, i.Name, i.CreatedDate, true));
            }
        }

        return new IntakeResponse(wrapped, totalRecords);
    }

    public class IntakeResponse {
        @AuraEnabled public List<IntakeWrapper> records;
        @AuraEnabled public Integer totalRecords;
        public IntakeResponse(List<IntakeWrapper> records, Integer totalRecords) {
            this.records = records;
            this.totalRecords = totalRecords;
        }
    }

    public class IntakeWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Boolean noFollowUp;
        public IntakeWrapper(Id id, String name, Datetime createdDate, Boolean noFollowUp) {
            this.id = id;
            this.name = name;
            this.createdDate = createdDate;
            this.noFollowUp = noFollowUp;
        }
    }
}