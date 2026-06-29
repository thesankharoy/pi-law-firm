/**
 * Entry point for the FAQ / objection knowledge base.
 *  - runMining(): extract candidates from completed-call transcripts (batch).
 *  - runClustering(): rebuild entries from candidates (deterministic).
 *  - runDrafting(): draft responses for top Draft clusters (queueable, callouts).
 */
public with sharing class FAQService {

    // Minimum cluster frequency to draft / treat as a coverage gap.
    // Defaults to 1 so thin dev orgs still produce drafts; raise (e.g. 3) in production.
    @TestVisible
    private static Integer minFreq = 1;

    public static Integer minFrequency() {
        return minFreq;
    }

    public static Id runMining() {
        return Database.executeBatch(new FAQMiningBatch(), WinLossConfig.batchScope());
    }

    public static void runClustering() {
        FAQClusteringService.rebuild();
    }

    public static Id runDrafting() {
        return System.enqueueJob(new FAQDraftJob());
    }
}