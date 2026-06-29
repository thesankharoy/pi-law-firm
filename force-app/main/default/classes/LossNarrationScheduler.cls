/**
 * Weekly/monthly cron entry: aggregates + narrates the configured lookback window.
 */
public class LossNarrationScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        WinLossService.runNarrationLastDays(null);
    }
}