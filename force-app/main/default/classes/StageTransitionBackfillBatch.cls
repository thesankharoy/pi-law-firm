/**
 * Seeds a baseline Stage_Transition__c for intakes that predate the trigger: one row to the
 * current status at the record's creation time, so they appear in the rate model. Full
 * intermediate history only accrues going forward from the trigger.
 */
public with sharing class StageTransitionBackfillBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id, Status__c, CreatedDate FROM Intake__c ' +
            'WHERE Status__c != null AND Id NOT IN (SELECT Intake__c FROM Stage_Transition__c WHERE Intake__c != null)');
    }

    public void execute(Database.BatchableContext bc, List<Intake__c> scope) {
        List<Stage_Transition__c> rows = new List<Stage_Transition__c>();
        for (Intake__c i : scope) {
            rows.add(new Stage_Transition__c(
                Intake__c = i.Id, To_Status__c = i.Status__c, Occurred_At__c = i.CreatedDate));
        }
        if (!rows.isEmpty()) insert rows;
    }

    public void finish(Database.BatchableContext bc) {}
}