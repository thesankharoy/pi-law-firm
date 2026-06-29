/**
 * Queueable (callout-allowed) that computes + narrates + delivers the conversion forecast in
 * its own transaction, so the Claude callout is clean of DML.
 */
public class ConversionForecastJob implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext ctx) {
        ConversionForecastService.run();
    }
}