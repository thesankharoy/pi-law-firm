trigger IntakeNotificationTrigger on Intake__c(after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        IntakeNotificationService.notifyAssignment(Trigger.new, null);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        IntakeNotificationService.notifyAssignment(Trigger.new, Trigger.oldMap);
        IntakeNotificationService.notifyRetainerSigned(Trigger.new, Trigger.oldMap);
    }
}
