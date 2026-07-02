global class IntakeFollowUpCleanupScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        // Batch size 200 — safe default well under governor limits for delete.
        Database.executeBatch(new IntakeFollowUpCleanupBatch(), 200);
    }

    // Runs at 2:00 AM every Sunday — change '2' to your BH start hour
    global static void schedule() {
        abortExisting();
        System.schedule('Intake Follow-Up Cleanup', '0 0 2 ? * SUN', new IntakeFollowUpCleanupScheduler());
    }

    private static void abortExisting() {
        for (CronTrigger ct : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = 'Intake Follow-Up Cleanup'
        ]) {
            System.abortJob(ct.Id);
        }
    }
}
