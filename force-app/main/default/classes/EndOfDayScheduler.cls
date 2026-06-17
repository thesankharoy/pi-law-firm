global class EndOfDayScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        // Order matters: mark first, then email
        // so the email captures the freshly marked Incomplete rows
        FollowUpEndOfDayService.markIncomplete();
        FollowUpEndOfDayService.emailPendingFollowUps();
    }

    global static void schedule() {
        String cron = '0 0 18 * * ?'; // 6:00 PM every day
        System.schedule('End of Day Follow-Up', cron, new EndOfDayScheduler());
    }
}
