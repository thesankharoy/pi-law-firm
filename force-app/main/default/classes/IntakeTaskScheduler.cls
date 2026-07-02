global class IntakeTaskScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        IntakeFollowUpService.createScheduledTasks();
    }

    global static void schedule() {
        abortExisting();
        // Runs at 9:00 AM daily — change '9' to your BH start hour
        System.schedule('Intake Follow-Up Tasks', '0 0 9 * * ?', new IntakeTaskScheduler());
    }

    private static void abortExisting() {
        for (CronTrigger ct : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = 'Intake Follow-Up Tasks'
        ]) {
            System.abortJob(ct.Id);
        }
    }
}