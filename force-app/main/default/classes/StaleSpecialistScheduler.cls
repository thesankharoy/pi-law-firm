global class StaleSpecialistScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        UserAvailabilityService.expireStaleSpecialists();
    }
}
// Schedule from Anonymous Apex:
// System.schedule('Expire Stale :00', '0 0 * * * ?', new StaleSpecialistScheduler());
// System.schedule('Expire Stale :05', '0 5 * * * ?', new StaleSpecialistScheduler());
// ... repeat for :10, :15, :20, :25, :30, :35, :40, :45, :50, :55