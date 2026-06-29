/**
 * Public entry point for the leak-alert pipeline. Call RevenueLeakService.run() from
 * anonymous Apex to scan on demand, or let RevenueLeakScheduler call it on a cron.
 */
public with sharing class RevenueLeakService {

    /** Enqueues the detection job (which chains narration + alerting). Returns the job id. */
    public static Id run() {
        return System.enqueueJob(new RevenueLeakDetectionJob());
    }
}