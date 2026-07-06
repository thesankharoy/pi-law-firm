global class IntakeFollowUpCleanupBatch implements Database.Batchable<sObject>, Database.Stateful {
    global Integer totalCompletedDeleted = 0;
    global Integer totalOrphanedDeleted = 0;
    global Integer totalFailed = 0;

    // Two independent conditions, either of which makes a row safe to
    // hard-delete:
    //
    // 1. Created__c = true — the row did its job. The Task records it
    //    spawned are the permanent record from here on; this tracking
    //    row has no further purpose.
    //
    // 2. Created__c = false AND the parent Intake's Status__c is now in
    //    the skip-status list (Turned Down, Referred Out, Retainer
    //    Agreement Signed, Converted). These rows are orphaned — the
    //    Intake left the follow-up flow before this scheduled step
    //    fired, and createScheduledTasks() will never touch it again
    //    because its skip-status check filters the parent out of the
    //    due-processing query permanently. Without this, a Turned Down
    //    intake leaves all of its still-pending Day-N rows in the
    //    database forever.
    //
    // A single combined query — rather than two separate batch jobs —
    // keeps this to one governor-limit-safe pass and one AsyncApexJob
    // history entry per week.
    global Database.QueryLocator start(Database.BatchableContext bc) {
        Set<String> skipStatuses = IntakeFollowUpService.getSkipStatuses();

        return Database.getQueryLocator(
            [
                SELECT Id, Created__c
                FROM Intake_Follow_Up__c
                WHERE Created__c = TRUE OR (Created__c = FALSE AND Intake__r.Status__c IN :skipStatuses)
            ]
        );
    }

    global void execute(Database.BatchableContext bc, List<Intake_Follow_Up__c> scope) {
        // Track which rows were completed vs orphaned before deleting,
        // for accurate reporting — Database.delete doesn't preserve
        // per-row context in its results.
        Map<Id, Boolean> wasCompletedById = new Map<Id, Boolean>();
        for (Intake_Follow_Up__c r : scope) {
            wasCompletedById.put(r.Id, r.Created__c);
        }

        List<Database.DeleteResult> results = Database.delete(scope, false);
        for (Database.DeleteResult r : results) {
            if (r.isSuccess()) {
                if (wasCompletedById.get(r.getId()) == true) {
                    totalCompletedDeleted++;
                } else {
                    totalOrphanedDeleted++;
                }
            } else {
                totalFailed++;
                for (Database.Error e : r.getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'Intake_Follow_Up__c cleanup delete failed: ' + e.getMessage());
                }
            }
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug(
            LoggingLevel.INFO,
            'IntakeFollowUpCleanupBatch finished — ' +
                totalCompletedDeleted +
                ' completed rows deleted, ' +
                totalOrphanedDeleted +
                ' orphaned rows deleted, ' +
                totalFailed +
                ' failed'
        );
    }
}