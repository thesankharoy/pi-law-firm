public without sharing class GenerateIntakeAuthDocsQueueable implements Queueable, Database.AllowsCallouts {

    public static final String DOC_TYPE_LOR       = 'Letter of Representation';
    public static final String DOC_TYPE_HIPAA     = 'HIPAA Authorization';
    public static final String DOC_TYPE_RETAINER  = 'Retainer Agreement';

    private static final String CONTENT_TYPE = 'application/pdf';

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

        // ── Retainer Agreement ───────────────────────────────────────────
        System.debug(LoggingLevel.INFO, '[AuthDocGen] Rendering Retainer Agreement for Intake=' + intakeId);
        try {
            Document__c retainerDoc = generateAndUpload(
                intakeId,
                DOC_TYPE_RETAINER,
                Page.RetainerAgreement,
                'Retainer Agreement - ' + intakeCheck[0].Name
            );
            if (retainerDoc != null) {
                docsToInsert.add(retainerDoc);
                System.debug(LoggingLevel.INFO, '[AuthDocGen] Retainer built — S3_Key=' + retainerDoc.S3_Key__c + ' Size=' + retainerDoc.File_Size__c);
            }
        } catch (Exception e) {
            logAndPersist(intakeId, 'Retainer Agreement generation threw: ' + e.getTypeName() + ': ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString());
        }

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
              AND  Document_Type__c IN (:DOC_TYPE_LOR, :DOC_TYPE_HIPAA, :DOC_TYPE_RETAINER)
            ORDER BY CreatedDate DESC
        ];
        System.debug(LoggingLevel.INFO, '[AuthDocGen] SOQL post-insert check — Document__c rows for Intake=' + intakeId + ': ' + savedDocs.size());
        for (Document__c d : savedDocs) {
            System.debug(LoggingLevel.INFO, '[AuthDocGen] Saved: Id=' + d.Id + ' Type=' + d.Document_Type__c + ' Key=' + d.S3_Key__c + ' Status=' + d.Status__c);
        }

        // Case-summary generation is intentionally NOT triggered here. It is a
        // fully separate flow, published independently from IntakeTriggerHandler
        // (Case_Summary_Generation__e). This job does documents only.

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

        // Build the key with the SAME service that presigns downloads/previews,
        // so upload and preview/download resolve to the same bucket + key.
        // buildKey() is pure (no callout) so it is safe to call in test context.
        String fileName = docName + '.pdf';
        String s3Key    = S3LambdaService.buildKey(intakeId, fileName);

        // In test context we skip the real presign + PUT callouts and just record the key.
        if (!Test.isRunningTest()) {
            Boolean uploaded = putToS3(intakeId, s3Key, pdfBlob, CONTENT_TYPE);
            if (!uploaded) {
                // putToS3 already logged the failure detail.
                return null;
            }
        }

        Document__c doc      = new Document__c();
        doc.Name             = docName;
        doc.Document_Type__c = documentType;
        doc.Intake__c        = intakeId;
        doc.S3_Key__c        = s3Key;
        doc.MIME_Type__c     = CONTENT_TYPE;
        doc.File_Size__c     = pdfBlob.size();
        doc.Status__c        = 'Active';
        return doc;
    }

    /**
     * Pre-signs a PUT via S3LambdaService (unchanged) and PUTs the bytes to the
     * returned presigned URL. Two callouts: one to the Lambda (via the
     * AWS_Lambda_NC named credential) to presign, one to S3 to store the bytes.
     *
     * NOTE: the PUT targets a raw S3 URL, so the S3 host needs a Remote Site
     * Setting (see MIGRATION_NOTES). The Content-Type header MUST match the
     * contentType passed to presignPut, or S3 rejects the signature.
     */
    private Boolean putToS3(Id intakeId, String s3Key, Blob body, String contentType) {
        try {
            String putUrl = S3LambdaService.presignPut(s3Key, contentType); // callout → Lambda

            HttpRequest req = new HttpRequest();
            req.setEndpoint(putUrl);
            req.setMethod('PUT');
            req.setHeader('Content-Type', contentType);
            req.setBodyAsBlob(body);
            req.setTimeout(120000);

            HttpResponse res = new Http().send(req); // callout → S3 (needs Remote Site Setting)
            Integer sc = res.getStatusCode();
            if (sc >= 200 && sc < 300) {
                System.debug(LoggingLevel.INFO, '[AuthDocGen] S3 PUT ok — key=' + s3Key + ' status=' + sc);
                return true;
            }
            logAndPersist(intakeId, 'S3 PUT failed for key ' + s3Key + ' — HTTP ' + sc + ': ' + res.getBody());
            return false;
        } catch (Exception e) {
            logAndPersist(intakeId, 'S3 PUT threw for key ' + s3Key + ': ' + e.getTypeName() + ': ' + e.getMessage());
            return false;
        }
    }

    private Blob renderPdf(PageReference vfPage, Id intakeId) {
        vfPage.getParameters().put('Id', String.valueOf(intakeId));
        try {
            // Runs as the licensed scheduling user, so getContent() renders natively.
            return Test.isRunningTest() ? Blob.valueOf('MOCK_PDF') : vfPage.getContent();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[AuthDocGen] getContent() threw for ' + intakeId + ': ' + e.getMessage());
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

    private void logAndPersist(Id relatedIntakeId, String message) {
        System.debug(LoggingLevel.ERROR, '[AuthDocGen] ERROR — Intake=' + relatedIntakeId + ' — ' + message);
        try {
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