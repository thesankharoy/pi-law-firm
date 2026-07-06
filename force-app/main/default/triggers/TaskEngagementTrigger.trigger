trigger TaskEngagementTrigger on Task(after insert, after update) {
    // Fires IntakeEngagementService.handleClientResponseUpdate whenever
    // a task is completed with Client_Responded__c = true — giving
    // immediate engagement recovery instead of waiting for the next
    // scheduled evaluate() pass.
    IntakeEngagementService.handleClientResponseUpdate(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}