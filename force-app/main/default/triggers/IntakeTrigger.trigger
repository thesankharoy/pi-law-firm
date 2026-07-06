trigger IntakeTrigger on Intake__c(before insert, before update, after insert, after update) {
    // ── BEFORE INSERT ────────────────────────────────────────────────────────
    if (Trigger.isBefore && Trigger.isInsert) {
        // Scope assignment engine + initial status to New_Intake ONLY.
        // Active_Intake or Converted_Intake created directly from the UI:
        // owner is whoever the user set, status is whatever the user set — untouched.
        Id newIntakeRtId = Schema.SObjectType.Intake__c
            .getRecordTypeInfosByDeveloperName()
            .get('New_Intake')
            .getRecordTypeId();

        List<Intake__c> newIntakes = new List<Intake__c>();
        for (Intake__c i : Trigger.new) {
            if (i.RecordTypeId == newIntakeRtId)
                newIntakes.add(i);
        }

        if (!newIntakes.isEmpty()) {
            // 1. Assignment engine stamps OwnerId (queue or user)
            IntakeAssignmentEngine.assignIntakes(newIntakes);
            // 2. Set Status based on who owns it after assignment
            IntakeLifecycleService.setInitialState(newIntakes);
            IntakeSpamFilterService.evaluate(newIntakes);
        }
    }

    // ── BEFORE UPDATE ────────────────────────────────────────────────────────
    if (Trigger.isBefore && Trigger.isUpdate) {
        IntakeLifecycleService.manageLifecycle(Trigger.new, Trigger.oldMap);
        IntakeTriggerHandler.flagOnSigning(Trigger.new, Trigger.oldMap);
    }

    // ── AFTER INSERT ─────────────────────────────────────────────────────────
    if (Trigger.isAfter && Trigger.isInsert) {
        IntakeFollowUpService.scheduleTasks(Trigger.new);
        IntakeNotificationService.notifyAssignment(Trigger.new, null);
        IntakeSpamFilterService.enqueueAITriage(Trigger.new);
    }

    // ── AFTER UPDATE ─────────────────────────────────────────────────────────
    if (Trigger.isAfter && Trigger.isUpdate) {
        IntakeFollowUpService.reassignTasks(Trigger.new, Trigger.oldMap);
        IntakeNotificationService.notifyAssignment(Trigger.new, Trigger.oldMap);
        IntakeNotificationService.notifyRetainerSigned(Trigger.new, Trigger.oldMap);
        IntakeTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        IntakeCaseSummaryHandler.handle(Trigger.new, Trigger.oldMap);
    }
}