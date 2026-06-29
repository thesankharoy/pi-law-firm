/**
 * Mines transcripts of completed intakes (signed OR lost) into FAQ_Candidate__c rows.
 * All callouts happen in the extract loop first, then DML. On finish it rebuilds the
 * clusters and kicks off the drafting job.
 */
public with sharing class FAQMiningBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {

    private static final Set<String> SIGNED = new Set<String>{ 'Retainer Agreement Signed', 'Converted' };

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Boolean hasTranscript = Schema.SObjectType.Intake__c.fields.getMap().containsKey('transcript__c');
        String fields = 'Id, Status__c, Incident_Description__c';
        if (hasTranscript) fields += ', Transcript__c';
        String q = 'SELECT ' + fields + ' FROM Intake__c '
            + 'WHERE Status__c IN (\'Retainer Agreement Signed\', \'Converted\', \'Turned Down\', \'Referred Out\') '
            + 'AND Id NOT IN (SELECT Intake__c FROM FAQ_Candidate__c WHERE Intake__c != null)';
        return Database.getQueryLocator(q);
    }

    public void execute(Database.BatchableContext bc, List<Intake__c> scope) {
        List<FAQ_Candidate__c> all = new List<FAQ_Candidate__c>();
        for (Intake__c i : scope) {
            try {
                all.addAll(FAQExtractionService.extract(i, SIGNED.contains(i.Status__c)));
            } catch (Exception e) {
                // skip a bad row rather than fail the whole execute
            }
        }
        if (!all.isEmpty()) insert all;
    }

    public void finish(Database.BatchableContext bc) {
        FAQService.runClustering();
        if (!Test.isRunningTest()) {
            FAQService.runDrafting();
        }
    }
}