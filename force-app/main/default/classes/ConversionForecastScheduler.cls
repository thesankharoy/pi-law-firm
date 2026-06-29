/**
 * Weekly cron entry: enqueues the conversion-forecast job.
 */
public class ConversionForecastScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        ConversionForecastService.enqueue();
    }
}