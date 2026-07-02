global class ConsultationReminderScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        ConsultationService.sendReminders();
    }

    global static void schedule() {
        abortExisting();
        System.schedule('Consultation Reminder :00', '0 0  * * * ?', new ConsultationReminderScheduler());
        System.schedule('Consultation Reminder :30', '0 30 * * * ?', new ConsultationReminderScheduler());
    }

    private static void abortExisting() {
        for (CronTrigger ct : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Consultation Reminder%'
        ]) {
            System.abortJob(ct.Id);
        }
    }
}