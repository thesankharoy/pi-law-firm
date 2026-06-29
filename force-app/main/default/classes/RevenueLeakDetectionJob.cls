/**
 * Queueable that runs detection (DML only) and then chains the narration job in a
 * fresh transaction, so the Anthropic callout never shares a transaction with the
 * leak-insert DML.
 */
public class RevenueLeakDetectionJob implements Queueable {

    public void execute(QueueableContext ctx) {
        RevenueLeakDetector.detectUnsignedRetainers();

        // Chain narration as a separate transaction. Skipped in tests, where chained
        // queueables don't execute and the narration job is exercised directly.
        if (!Test.isRunningTest()) {
            System.enqueueJob(new RevenueLeakNarrationJob());
        }
    }
}