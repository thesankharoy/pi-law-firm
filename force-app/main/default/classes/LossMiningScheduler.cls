/**
 * Nightly cron entry: runs the extraction batch.
 */
public class LossMiningScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        WinLossService.runExtraction();
    }
}