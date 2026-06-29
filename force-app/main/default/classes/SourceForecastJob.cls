/**
 * Queueable (callout-allowed) that rolls up, projects, narrates, and delivers the source
 * quality forecast in its own transaction.
 */
public class SourceForecastJob implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext ctx) {
        SourceForecastService.run();
    }
}