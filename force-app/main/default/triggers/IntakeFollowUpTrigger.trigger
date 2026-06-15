trigger IntakeFollowUpTrigger on Intake__c(after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        IntakeFollowUpService.scheduleTasks(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        IntakeFollowUpService.reassignTasks(Trigger.new, Trigger.oldMap);
    }
}