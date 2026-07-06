/**
 * Writes an append-only Stage_Transition__c row whenever an Intake is created or its Status
 * changes. Runs `without sharing` because it is system instrumentation that must fire for ALL
 * users — including the Site Guest User — regardless of record-level access to the parent Intake.
 * Inserting Stage_Transition__c does not re-fire the Intake trigger.
 */
public without sharing class StageTransitionHandler {
    public static void handleInsert(List<Intake__c> news) {
        List<Stage_Transition__c> rows = new List<Stage_Transition__c>();
        for (Intake__c i : news) {
            rows.add(new Stage_Transition__c(
                Intake__c = i.Id, From_Status__c = null, To_Status__c = i.Status__c,
                Occurred_At__c = System.now()));
        }
        if (!rows.isEmpty()) insert rows;
    }
    public static void handleUpdate(List<Intake__c> news, Map<Id, Intake__c> oldMap) {
        List<Stage_Transition__c> rows = new List<Stage_Transition__c>();
        for (Intake__c i : news) {
            Intake__c o = oldMap.get(i.Id);
            if (o != null && i.Status__c != o.Status__c) {
                rows.add(new Stage_Transition__c(
                    Intake__c = i.Id, From_Status__c = o.Status__c, To_Status__c = i.Status__c,
                    Occurred_At__c = System.now()));
            }
        }
        if (!rows.isEmpty()) insert rows;
    }
}