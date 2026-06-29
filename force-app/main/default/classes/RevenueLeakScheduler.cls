/**
 * Cron entry point. Schedule four instances for an every-15-minute cadence (see README).
 * Each fire enqueues the detection job, which chains narration + alerting.
 */
public class RevenueLeakScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        RevenueLeakService.run();
    }
}