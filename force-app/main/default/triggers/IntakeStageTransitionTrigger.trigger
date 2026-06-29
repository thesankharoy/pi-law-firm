/**
 * Dedicated, additive trigger that logs Intake status changes to Stage_Transition__c.
 * Kept separate from the existing IntakeTrigger so this feature doesn't modify it.
 */
trigger IntakeStageTransitionTrigger on Intake__c (after insert, after update) {
    if (Trigger.isInsert) {
        StageTransitionHandler.handleInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
        StageTransitionHandler.handleUpdate(Trigger.new, Trigger.oldMap);
    }
}