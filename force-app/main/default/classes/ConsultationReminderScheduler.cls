global class ConsultationReminderScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        ConsultationService.sendReminders();
    }

    global static void schedule() {
        System.schedule('Consultation Reminder :00', '0 0  * * * ?', new ConsultationReminderScheduler());
        System.schedule('Consultation Reminder :30', '0 30 * * * ?', new ConsultationReminderScheduler());
    }
}
