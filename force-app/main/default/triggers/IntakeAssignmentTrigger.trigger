trigger IntakeAssignmentTrigger on Intake__c(before insert) {
    IntakeAssignmentEngine.assignIntakes(Trigger.new);
}
