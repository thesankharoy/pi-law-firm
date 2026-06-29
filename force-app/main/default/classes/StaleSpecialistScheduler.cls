global class StaleSpecialistScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        UserAvailabilityService.expireStaleSpecialists();
    }

    global static void schedule() {
        List<String> times = new List<String>{ '00', '05', '10', '15', '20', '25', '30', '35', '40', '45', '50', '55' };
        for (String t : times) {
            System.schedule('Expire Stale :' + t, '0 ' + t + ' * * * ?', new StaleSpecialistScheduler());
        }
    }
}
// Schedule from Anonymous Apex:
// System.schedule('Expire Stale :00', '0 0 * * * ?', new StaleSpecialistScheduler());
// System.schedule('Expire Stale :05', '0 5 * * * ?', new StaleSpecialistScheduler());
// ... repeat for :10, :15, :20, :25, :30, :35, :40, :45, :50, :55