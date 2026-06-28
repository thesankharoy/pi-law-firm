global class DripCampaignScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        DripCampaignService.processEnrollments();
    }

    // Run from Anonymous Apex once to register the daily 8am job
    global static void schedule() {
        System.schedule('Drip Campaign Processor', '0 0 8 * * ?', new DripCampaignScheduler());
    }
}
