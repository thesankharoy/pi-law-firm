/**
 * CaseSummaryController
 *
 * @AuraEnabled façade for the caseSummaryPanel LWC.
 * Provides read of the current summary and a regenerate action
 * (specialist-initiated re-run).
 */
public with sharing class CaseSummaryController {

    /**
     * Returns the current summary text, generated-at timestamp, and review flag.
     * Cacheable so the wire can refresh without a full page reload.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getSummary(Id intakeId) {
        try {
            Intake__c rec = [
                SELECT Case_Summary__c, Summary_Generated_At__c, Summary_Reviewed__c,
                       Status__c, Name
                FROM   Intake__c
                WHERE  Id = :intakeId
                LIMIT  1
            ];
            return new Map<String, Object>{
                'summary'       => rec.Case_Summary__c,
                'generatedAt'   => rec.Summary_Generated_At__c,
                'reviewed'      => rec.Summary_Reviewed__c,
                'intakeName'    => rec.Name,
                'status'        => rec.Status__c
            };
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Marks the summary as reviewed / unreviewed.
     * Called when the specialist ticks the "Reviewed" checkbox in the panel.
     */
    @AuraEnabled
    public static void setReviewed(Id intakeId, Boolean reviewed) {
        try {
            update new Intake__c(
                Id                   = intakeId,
                Summary_Reviewed__c  = reviewed
            );
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Saves a specialist's manual edits to the summary text.
     * Called from the LWC inline editor — avoids the need for dynamic imports
     * or uiRecordApi updateRecord (which is unreliable for Long Text Area fields).
     */
    @AuraEnabled
    public static void saveSummary(Id intakeId, String summaryText) {
        try {
            update new Intake__c(
                Id              = intakeId,
                Case_Summary__c = summaryText
            );
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Re-enqueues CaseSummaryQueueable so the specialist can regenerate the
     * summary if the intake was updated after the original signing.
     */
    @AuraEnabled
    public static void regenerateSummary(Id intakeId) {
        try {
            // Verify intake is in a signed state before regenerating
            Intake__c rec = [
                SELECT Status__c FROM Intake__c WHERE Id = :intakeId LIMIT 1
            ];
            if (rec.Status__c != 'Retainer Agreement Signed') {
                throw new AuraHandledException(
                    'Summary can only be generated for signed intakes.'
                );
            }
            System.enqueueJob(new CaseSummaryQueueable(intakeId));
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Could not queue regeneration: ' + e.getMessage());
        }
    }
}