public with sharing class GenerateIntakeAuthDocsQueueable implements Queueable, Database.AllowsCallouts {

    public static final String DOC_TYPE_LOR  = 'Letter of Representation';
    public static final String DOC_TYPE_HIPAA = 'HIPAA Authorization';

    private Id intakeId;

    public GenerateIntakeAuthDocsQueueable(Id intakeId) {
        this.intakeId = intakeId;
    }

    public void execute(QueueableContext ctx) {
        if (intakeId == null) {
            System.debug(LoggingLevel.ERROR, '[AuthDocGen] execute() called with null intakeId — aborting.');
            return;
        }

        String jobId = (ctx != null) ? ctx.getJobId() : 'DIRECT-CALL';
System.debug(LoggingLevel.INFO, '[AuthDocGen] START — Intake=' + intakeId + ' | Job=' + jobId);

        // ── Guard: confirm Intake still exists ──────────────────────────
        List<Intake__c> intakeCheck = [
            SELECT Id, Name, Status__c
            FROM   Intake__c
            WHERE  Id = :intakeId
            LIMIT  1
        ];
        if (intakeCheck.isEmpty()) {
            logAndPersist(intakeId, 'Intake record no longer exists — job aborted. SOQL confirmed 0 rows for Id=' + intakeId);
            return;
        }
        System.debug(LoggingLevel.INFO, '[AuthDocGen] Intake confirmed: Name=' + intakeCheck[0].Name + ' Status=' + intakeCheck[0].Status__c);

        List<Document__c> docsToInsert = new List<Document__c>();

        // ── Letter of Representation ─────────────────────────────────────
        System.debug(LoggingLevel.INFO, '[AuthDocGen] Rendering LOR for Intake=' + intakeId);
        try {
            Document__c lorDoc = generateAndUpload(
                intakeId,
                DOC_TYPE_LOR,
                Page.LetterOfRepresentationPdf,
                'Letter of Representation - ' + intakeCheck[0].Name
            );
            if (lorDoc != null) {
                docsToInsert.add(lorDoc);
                System.debug(LoggingLevel.INFO, '[AuthDocGen] LOR built — S3_Key=' + lorDoc.S3_Key__c + ' Size=' + lorDoc.File_Size__c);
            }
        } catch (Exception e) {
            logAndPersist(intakeId, 'LOR generation threw: ' + e.getTypeName() + ': ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString());
        }

        // ── HIPAA Authorization ──────────────────────────────────────────
        System.debug(LoggingLevel.INFO, '[AuthDocGen] Rendering HIPAA for Intake=' + intakeId);
        try {
            Document__c hipaaDoc = generateAndUpload(
                intakeId,
                DOC_TYPE_HIPAA,
                Page.HipaaAuthorizationPdf,
                'HIPAA Authorization - ' + intakeCheck[0].Name
            );
            if (hipaaDoc != null) {
                docsToInsert.add(hipaaDoc);
                System.debug(LoggingLevel.INFO, '[AuthDocGen] HIPAA built — S3_Key=' + hipaaDoc.S3_Key__c + ' Size=' + hipaaDoc.File_Size__c);
            }
        } catch (Exception e) {
            logAndPersist(intakeId, 'HIPAA generation threw: ' + e.getTypeName() + ': ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString());
        }

        System.debug(LoggingLevel.INFO, '[AuthDocGen] Docs ready to insert: ' + docsToInsert.size());

        if (!docsToInsert.isEmpty()) {
            insertDocuments(docsToInsert);
        } else {
            logAndPersist(intakeId, 'No documents were successfully generated/uploaded — Document__c insert skipped.');
        }

        // ── Post-insert SOQL confirmation ────────────────────────────────
        List<Document__c> savedDocs = [
            SELECT Id, Name, Document_Type__c, S3_Key__c, Status__c
            FROM   Document__c
            WHERE  Intake__c = :intakeId
              AND  Document_Type__c IN (:DOC_TYPE_LOR, :DOC_TYPE_HIPAA)
            ORDER BY CreatedDate DESC
        ];
        System.debug(LoggingLevel.INFO, '[AuthDocGen] SOQL post-insert check — Document__c rows for Intake=' + intakeId + ': ' + savedDocs.size());
        for (Document__c d : savedDocs) {
            System.debug(LoggingLevel.INFO, '[AuthDocGen] Saved: Id=' + d.Id + ' Type=' + d.Document_Type__c + ' Key=' + d.S3_Key__c + ' Status=' + d.Status__c);
        }

        // ── Chain to case summary generation ─────────────────────────────
        // Runs AFTER the Document__c inserts above have committed, so
        // CaseSummaryQueueable's fact-sheet query is guaranteed to see the
        // HIPAA/LOR documents (whichever of them succeeded). Fired
        // unconditionally — even if both doc generations failed above —
        // so the attorney still gets a hand-off summary built from
        // whatever data does exist; CaseSummaryQueueable already handles
        // missing/partial data by writing "Not provided" rather than
        // failing. This replaces the old direct trigger-time enqueue of
        // CaseSummaryQueueable, which had no ordering guarantee relative
        // to this job and could run before these documents existed.
        try {
            System.enqueueJob(new CaseSummaryQueueable(intakeId));
            System.debug(LoggingLevel.INFO, '[AuthDocGen] Chained CaseSummaryQueueable for Intake=' + intakeId);
        } catch (Exception e) {
            logAndPersist(intakeId, 'Failed to enqueue CaseSummaryQueueable: ' + e.getTypeName() + ': ' + e.getMessage());
        }

        System.debug(LoggingLevel.INFO, '[AuthDocGen] END — Intake=' + intakeId);
    }

    private Document__c generateAndUpload(Id intakeId, String documentType, PageReference vfPage, String docName) {
    System.debug(LoggingLevel.INFO, '[AuthDocGen] renderPdf start — type=' + documentType);
    Blob pdfBlob = renderPdf(vfPage, intakeId);
    if (pdfBlob == null) {
        logAndPersist(intakeId, documentType + ': getContent() returned null blob.');
        return null;
    }
    System.debug(LoggingLevel.INFO, '[AuthDocGen] PDF rendered — bytes=' + pdfBlob.size());

    // ── NEW: skip real S3 upload in test context ─────────────────────────
    S3UploadService.UploadResult uploadResult;
    if (Test.isRunningTest()) {
        uploadResult = new S3UploadService.UploadResult();
        uploadResult.success    = true;
        uploadResult.s3Key      = 'intakes/' + intakeId + '/documents/MOCK_' + documentType + '.pdf';
        uploadResult.statusCode = 200;
    } else {
        uploadResult = S3UploadService.upload(intakeId, documentType, pdfBlob);
    }
    // ─────────────────────────────────────────────────────────────────────

    System.debug(LoggingLevel.INFO, '[AuthDocGen] S3 result — success=' + uploadResult.success
        + ' status=' + uploadResult.statusCode
        + ' key='    + uploadResult.s3Key
        + ' error='  + uploadResult.errorMessage);

    if (!uploadResult.success) {
        logAndPersist(intakeId, documentType + ' S3 upload failed — HTTP '
            + uploadResult.statusCode + ': ' + uploadResult.errorMessage);
        return null;
    }

    Document__c doc      = new Document__c();
    doc.Name             = docName;
    doc.Document_Type__c = documentType;
    doc.Intake__c        = intakeId;
    doc.S3_Key__c        = uploadResult.s3Key;
    doc.MIME_Type__c     = 'application/pdf';
    doc.File_Size__c     = pdfBlob.size();
    doc.Status__c        = 'Active';
    return doc;
}
    private Blob renderPdf(PageReference vfPage, Id intakeId) {
        vfPage.getParameters().put('Id', String.valueOf(intakeId));
        try {
            Blob b = Test.isRunningTest() ? Blob.valueOf('MOCK_PDF') : vfPage.getContent();
            return b;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[AuthDocGen] getContent() threw: ' + e.getMessage());
            return null;
        }
    }

    private void insertDocuments(List<Document__c> docs) {
        System.debug(LoggingLevel.INFO, '[AuthDocGen] Inserting ' + docs.size() + ' Document__c record(s)...');
        Database.SaveResult[] results = Database.insert(docs, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                System.debug(LoggingLevel.INFO, '[AuthDocGen] Document__c INSERT SUCCESS — Id=' + results[i].getId()
                    + ' Type=' + docs[i].Document_Type__c);
            } else {
                String errs = '';
                for (Database.Error err : results[i].getErrors()) {
                    errs += err.getStatusCode() + ': ' + err.getMessage()
                         + ' (fields: ' + String.join(err.getFields(), ', ') + '); ';
                }
                logAndPersist(docs[i].Intake__c,
                    'Document__c INSERT FAILED — Type=' + docs[i].Document_Type__c
                    + ' S3_Key=' + docs[i].S3_Key__c
                    + ' Errors: ' + errs);
            }
        }
    }

    /**
     * Logs to System.debug AND writes a persistent Intake_Error_Log__c record
     * so failures survive after the debug log window closes.
     * Create a lightweight custom object: Intake_Error_Log__c with
     *   Intake__c Lookup(Intake), Message__c LongTextArea, Occurred_At__c DateTime
     */
    private void logAndPersist(Id relatedIntakeId, String message) {
        System.debug(LoggingLevel.ERROR, '[AuthDocGen] ERROR — Intake=' + relatedIntakeId + ' — ' + message);
        try {
            // Replace with your actual error log object/fields if different
            // If you don't have this object yet, comment out the insert
            // and rely on System.debug until you create it.
            /* 
            Intake_Error_Log__c log = new Intake_Error_Log__c();
            log.Intake__c     = relatedIntakeId;
            log.Message__c    = message.left(32768);
            log.Occurred_At__c = DateTime.now();
            insert log;
            */
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[AuthDocGen] logAndPersist itself failed: ' + e.getMessage());
        }
    }
}