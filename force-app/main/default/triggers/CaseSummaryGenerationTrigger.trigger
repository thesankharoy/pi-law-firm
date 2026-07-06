/**
 * CaseSummaryGenerationTrigger
 *
 * The case-summary flow, fully separated from document generation. Runs as the
 * AUTOMATED PROCESS system user (all platform-event triggers do), so it has full
 * record access and is completely isolated from GenerateIntakeAuthDocsQueueable:
 * a failure here can never affect the PDFs or the S3 uploads.
 *
 * GenerateIntakeAuthDocsQueueable publishes Case_Summary_Generation__e AFTER the
 * Document__c rows are committed (publish-after-commit), so CaseSummaryQueueable
 * still sees the LOR / HIPAA / Retainer docs on file when it runs.
 */
trigger CaseSummaryGenerationTrigger on Case_Summary_Generation__e (after insert) {
    for (Case_Summary_Generation__e evt : Trigger.New) {
        if (String.isBlank(evt.Intake_Id__c)) {
            System.debug(LoggingLevel.ERROR, '[CaseSummaryEvt] Skipped — blank Intake_Id__c on event ' + evt.ReplayId);
            continue;
        }
        try {
            System.enqueueJob(new CaseSummaryQueueable((Id) evt.Intake_Id__c));
            System.debug(LoggingLevel.INFO, '[CaseSummaryEvt] Enqueued case summary for Intake=' + evt.Intake_Id__c
                + ' as ' + UserInfo.getUserName() + ' (' + UserInfo.getUserType() + ')');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[CaseSummaryEvt] enqueue failed for '
                + evt.Intake_Id__c + ': ' + e.getTypeName() + ': ' + e.getMessage());
        }
    }
}