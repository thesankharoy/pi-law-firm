public class IntakeCaseSummaryHandler {
    @TestVisible
    private static final String SIGNED_STATUS = 'Retainer Agreement Signed';

    public static void handle(List<Intake__c> newList, Map<Id, Intake__c> oldMap) {
        // Intentionally a no-op now — see class comment.
        // CaseSummaryQueueable is enqueued by GenerateIntakeAuthDocsQueueable
        // once HIPAA/LOR documents are generated and committed.
    }
}