/**
 * Queueable (callout-allowed) that aggregates losses over a window, narrates the digest,
 * and delivers it. Runs in its own transaction so the callout is clean of DML.
 */
public class LossNarrationJob implements Queueable, Database.AllowsCallouts {

    private Integer lookbackDays;

    public LossNarrationJob(Integer lookbackDays) {
        this.lookbackDays = lookbackDays;
    }

    public void execute(QueueableContext ctx) {
        LossAggregationService.Aggregates a = LossAggregationService.aggregate(lookbackDays);
        LossNarrationService.NarrationResult n = LossNarrationService.narrate(a);
        WinLossAlertService.deliver(n, a);
    }
}