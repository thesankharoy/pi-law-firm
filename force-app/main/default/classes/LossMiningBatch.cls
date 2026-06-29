/**
 * Nightly extraction. For each newly-lost intake (Turned Down / Referred Out with no
 * analysis yet), classifies the transcript. All callouts happen first (in the per-row
 * extract loop), THEN the records are inserted — so a callout never follows DML.
 *
 * The Transcript__c field is describe-guarded: if the org doesn't have it, the query and
 * extraction fall back to Incident_Description__c and the package still works.
 */
public with sharing class LossMiningBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Boolean hasTranscript = Schema.SObjectType.Intake__c.fields.getMap().containsKey('transcript__c');
        String fields = 'Id, Incident_Type__c, Source__c, Incident_Description__c, '
            + 'Turn_Down_Reason__c, Turn_Down_Details__c, OwnerId';
        if (hasTranscript) {
            fields += ', Transcript__c';
        }
        String q = 'SELECT ' + fields + ' FROM Intake__c '
            + 'WHERE Status__c IN (\'Turned Down\', \'Referred Out\') '
            + 'AND Id NOT IN (SELECT Intake__c FROM Loss_Analysis__c WHERE Intake__c != null)';
        return Database.getQueryLocator(q);
    }

    public void execute(Database.BatchableContext bc, List<Intake__c> scope) {
        List<LossExtractionService.ExtractionResult> results =
            new List<LossExtractionService.ExtractionResult>();

        // 1) all callouts first
        for (Intake__c i : scope) {
            try {
                results.add(LossExtractionService.extract(i));
            } catch (Exception e) {
                // skip a row that blows up rather than failing the whole execute
            }
        }

        // 2) then DML
        List<Loss_Analysis__c> analyses = new List<Loss_Analysis__c>();
        for (LossExtractionService.ExtractionResult r : results) {
            analyses.add(r.analysis);
        }
        if (analyses.isEmpty()) return;
        insert analyses;

        List<Objection__c> objs = new List<Objection__c>();
        for (LossExtractionService.ExtractionResult r : results) {
            for (Objection__c o : r.objections) {
                o.Loss_Analysis__c = r.analysis.Id;
                objs.add(o);
            }
        }
        if (!objs.isEmpty()) insert objs;
    }

    public void finish(Database.BatchableContext bc) {}
}