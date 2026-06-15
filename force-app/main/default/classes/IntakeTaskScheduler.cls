global class IntakeTaskScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        IntakeFollowUpService.createScheduledTasks();
    }

    global static void schedule() {
        // Runs at 9:00 AM daily — change '9' to your BH start hour
        System.schedule('Intake Follow-Up Tasks', '0 0 9 * * ?', new IntakeTaskScheduler());
    }
}
