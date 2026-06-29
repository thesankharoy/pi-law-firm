/**
 * IntakeCaseSummaryHandler
 *
 * NOTE — ordering fix:
 * This handler USED to enqueue CaseSummaryQueueable directly from
 * IntakeTrigger (after update) on the Retainer Agreement Signed transition.
 * That raced against GenerateIntakeAuthDocsQueueable (also enqueued on the
 * same status transition, from IntakeTriggerHandler.handleAfterUpdate):
 * two independently-enqueued Queueables have NO execution-order guarantee
 * relative to each other in Salesforce, so the case summary could be (and
 * was) generated before the HIPAA/LOR Document__c records existed.
 *
 * Fix: CaseSummaryQueueable is now enqueued from inside
 * GenerateIntakeAuthDocsQueueable.execute(), AFTER its document inserts are
 * committed. This handler is intentionally left empty / unused so the
 * trigger no longer double-enqueues the summary job. It is kept (rather
 * than deleted) so the call site in IntakeTrigger doesn't need to be
 * touched, and so the history of this decision is visible to the next
 * person who reads this trigger.
 *
 * Do not re-add System.enqueueJob(new CaseSummaryQueueable(...)) here —
 * that reintroduces the race.
 */
public class IntakeCaseSummaryHandler {
    @TestVisible
    private static final String SIGNED_STATUS = 'Retainer Agreement Signed';

    public static void handle(List<Intake__c> newList, Map<Id, Intake__c> oldMap) {
        // Intentionally a no-op now — see class comment.
        // CaseSummaryQueueable is enqueued by GenerateIntakeAuthDocsQueueable
        // once HIPAA/LOR documents are generated and committed.
    }
}