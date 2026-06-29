/**
 * Monthly cron entry: re-mines transcripts (which then re-clusters + re-drafts on finish).
 */
public class FAQScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        FAQService.runMining();
    }
}