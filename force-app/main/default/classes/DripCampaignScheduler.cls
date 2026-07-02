global class DripCampaignScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        DripCampaignService.processEnrollments();
    }

    // Run from Anonymous Apex once to register the daily 8am job
    global static void schedule() {
        abortExisting();
        System.schedule('Drip Campaign Processor', '0 0 8 * * ?', new DripCampaignScheduler());
    }

    private static void abortExisting() {
        for (CronTrigger ct : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = 'Drip Campaign Processor'
        ]) {
            System.abortJob(ct.Id);
        }
    }
}