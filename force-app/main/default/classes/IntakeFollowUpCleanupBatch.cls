global class IntakeFollowUpCleanupBatch implements Database.Batchable<sObject>, Database.Stateful {
    global Integer totalDeleted = 0;
    global Integer totalFailed = 0;

    // Only completed tracking records — once Created__c = true, the
    // Task records it spawned are the permanent record from here on
    // and this row has no further purpose.
    // Pending (Created__c = false) rows are intentionally excluded.
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            [
                SELECT Id
                FROM Intake_Follow_Up__c
                WHERE Created__c = TRUE
            ]
        );
    }

    global void execute(Database.BatchableContext bc, List<Intake_Follow_Up__c> scope) {
        // allOrNone=false — a single locked/undeletable row (e.g. a
        // stray sharing rule or validation issue) should never block
        // the rest of the batch from being cleaned up.
        List<Database.DeleteResult> results = Database.delete(scope, false);
        for (Database.DeleteResult r : results) {
            if (r.isSuccess()) {
                totalDeleted++;
            } else {
                totalFailed++;
                for (Database.Error e : r.getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'Intake_Follow_Up__c cleanup delete failed: ' + e.getMessage());
                }
            }
        }
    }

    global void finish(Database.BatchableContext bc) {
        // every run leaves a trace so a silently-stalled cleanup job is never invisible.
        System.debug(
            LoggingLevel.INFO,
            'IntakeFollowUpCleanupBatch finished — ' + totalDeleted + ' deleted, ' + totalFailed + ' failed'
        );
    }
}
