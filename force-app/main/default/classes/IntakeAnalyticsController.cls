public with sharing class IntakeAnalyticsController {

    @AuraEnabled(cacheable=true)
    public static IntakeResponse getIntakes(Integer pageSize, Integer pageNumber) {

        Integer offsetSize = (pageNumber - 1) * pageSize;

        List<Intake__c> intakes = [
            SELECT Id, Name, CreatedDate
            FROM Intake__c
            ORDER BY CreatedDate DESC
            LIMIT :pageSize
            OFFSET :offsetSize
        ];

        Integer totalRecords = [
            SELECT COUNT()
            FROM Intake__c
        ];

        Set<Id> intakeIds = new Set<Id>();
        for (Intake__c i : intakes) {
            intakeIds.add(i.Id);
        }

        Set<Id> intakesWithTask = new Set<Id>();

        for (Task t : [
            SELECT WhatId
            FROM Task
            WHERE WhatId IN :intakeIds
        ]) {
            if (t.WhatId != null) {
                intakesWithTask.add(t.WhatId);
            }
        }

        List<IntakeWrapper> wrapped = new List<IntakeWrapper>();

        for (Intake__c i : intakes) {

            Boolean noFollowUp = !intakesWithTask.contains(i.Id);

            wrapped.add(new IntakeWrapper(
                i.Id,
                i.Name,
                i.CreatedDate,
                noFollowUp
            ));
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