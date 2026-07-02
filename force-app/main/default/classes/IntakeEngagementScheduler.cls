global class IntakeEngagementScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        IntakeEngagementService.evaluate();
    }

    // Schedule from Anonymous Apex — runs every 4 hours
    global static void schedule() {
        abortExisting();
        System.schedule('Engagement Engine 00:00', '0 0  0  * * ?', new IntakeEngagementScheduler());
        System.schedule('Engagement Engine 04:00', '0 0  4  * * ?', new IntakeEngagementScheduler());
        System.schedule('Engagement Engine 08:00', '0 0  8  * * ?', new IntakeEngagementScheduler());
        System.schedule('Engagement Engine 12:00', '0 0  12 * * ?', new IntakeEngagementScheduler());
        System.schedule('Engagement Engine 16:00', '0 0  16 * * ?', new IntakeEngagementScheduler());
        System.schedule('Engagement Engine 20:00', '0 0  20 * * ?', new IntakeEngagementScheduler());
    }

    private static void abortExisting() {
        for (CronTrigger ct : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Engagement Engine%'
        ]) {
            System.abortJob(ct.Id);
        }
    }
}