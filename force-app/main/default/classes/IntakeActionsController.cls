public with sharing class IntakeActionsController {
    @AuraEnabled
    public static string updateIntakeStatus(Id recordId, String statusValue){
        try {
            Intake__c intake = [Select Id, Status__c from Intake__c where Id =: recordId LIMIT 1];
            intake.Status__c = statusValue;
            update intake;
            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}