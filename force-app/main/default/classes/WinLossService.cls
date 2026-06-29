/**
 * Public entry point for the win/loss pipeline. Run on demand from anonymous Apex, or let
 * the schedulers call these on a cron.
 */
public with sharing class WinLossService {

    /** Kicks off the nightly extraction batch. Returns the batch job id. */
    public static Id runExtraction() {
        return Database.executeBatch(new LossMiningBatch(), WinLossConfig.batchScope());
    }

    /** Aggregates + narrates the last N days (defaults to configured lookback). Returns the job id. */
    public static Id runNarrationLastDays(Integer days) {
        Integer d = (days == null || days < 1) ? WinLossConfig.lookbackDays() : days;
        return System.enqueueJob(new LossNarrationJob(d));
    }
}