/**
 * @AuraEnabled facade for the intakeDocumentAnalyzer LWC.
 * Lists an intake's files with their analysis status, returns a cached analysis,
 * and triggers a fresh Claude analysis on demand.
 */
public with sharing class DocumentAnalysisController {
    /** A file row plus whether it has been (or can be) analyzed. */
    public class FileRow {
        @AuraEnabled public Id documentId;
        @AuraEnabled public String name;
        @AuraEnabled public String mimeType;
        @AuraEnabled public Boolean analyzable;   // supported file type?
        @AuraEnabled public Boolean analyzed;      // cached completed analysis exists?
        @AuraEnabled public String documentType;   // from cache, if analyzed
        @AuraEnabled public String analyzedOnLabel; // from cache, if analyzed
    }

    @AuraEnabled(cacheable=false)
    public static List<FileRow> listDocuments(Id intakeId) {
        List<Document__c> docs = [
            SELECT Id, Name, MIME_Type__c
            FROM Document__c
            WHERE Intake__c = :intakeId AND (Status__c = 'Active' OR Status__c = null)
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];

        // One query for all completed analyses under this intake → cache map.
        Map<Id, Document_Analysis__c> byDoc = new Map<Id, Document_Analysis__c>();
        for (Document_Analysis__c a : [
            SELECT Document__c, Document_Type__c, Analyzed_On__c
            FROM Document_Analysis__c
            WHERE Intake__c = :intakeId AND Status__c = 'Completed'
            ORDER BY Analyzed_On__c ASC NULLS FIRST
        ]) {
            byDoc.put(a.Document__c, a); // later (newer) wins
        }

        List<FileRow> rows = new List<FileRow>();
        for (Document__c d : docs) {
            FileRow r = new FileRow();
            r.documentId = d.Id;
            r.name = d.Name;
            r.mimeType = d.MIME_Type__c;
            r.analyzable = DocumentAnalysisService.isAnalyzable(d.Name, d.MIME_Type__c);
            Document_Analysis__c a = byDoc.get(d.Id);
            r.analyzed = a != null;
            if (a != null) {
                r.documentType = a.Document_Type__c;
                r.analyzedOnLabel = a.Analyzed_On__c == null
                    ? null
                    : a.Analyzed_On__c.format('MMM d, yyyy, h:mm a');
            }
            rows.add(r);
        }
        return rows;
    }

    @AuraEnabled(cacheable=false)
    public static DocumentAnalysisService.AnalysisDTO getAnalysis(Id documentId) {
        return DocumentAnalysisService.getCached(documentId);
    }

    @AuraEnabled
    public static DocumentAnalysisService.AnalysisDTO analyzeDocument(Id documentId, Boolean force) {
        return DocumentAnalysisService.analyze(documentId, force == true);
    }
}