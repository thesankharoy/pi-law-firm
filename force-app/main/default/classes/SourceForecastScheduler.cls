/**
 * Scheduled entry: enqueues the source-quality forecast job.
 */
public class SourceForecastScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        SourceForecastService.enqueue();
    }
}