public without sharing class DocumentFileService {
    private static final Integer MULTIPART_THRESHOLD = 10 * 1024 * 1024; // 10 MB

    public class FileDTO {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String s3Key;
        @AuraEnabled
        public Long fileSize;
        @AuraEnabled
        public String mimeType;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String createdDate;
        @AuraEnabled
        public String createdBy;
        @AuraEnabled
        public String uploadId;
    }

    public class UploadInitResult {
        @AuraEnabled
        public Id fileRecordId;
        @AuraEnabled
        public String s3Key;
        @AuraEnabled
        public String uploadId; // null for single-part
        @AuraEnabled
        public String presignedUrl; // set for single-part
        @AuraEnabled
        public List<Object> partUrls; // set for multipart
        @AuraEnabled
        public Integer totalParts;
        @AuraEnabled
        public Boolean isMultipart;
    }

    // ── List files in a folder ─────────────────────────────────────
    public static List<FileDTO> listFiles(Id folderId) {
        List<FileDTO> result = new List<FileDTO>();
        for (Document__c f : [
            SELECT
                Id,
                Name,
                S3_Key__c,
                File_Size__c,
                MIME_Type__c,
                Status__c,
                Notes__c,
                Upload_ID__c,
                CreatedDate,
                CreatedBy.Name
            FROM Document__c
            WHERE Folder__c = :folderId AND Status__c != 'Deleted'
            ORDER BY Name ASC
        ])
            result.add(toDTO(f));
        return result;
    }

    // ── Initiate upload — creates the metadata record and pre-signs ─
    public static UploadInitResult initiateUpload(
        Id intakeId,
        Id folderId,
        String fileName,
        Long fileSize,
        String contentType
    ) {
        String s3Key = S3LambdaService.buildKey(intakeId, fileName);

        UploadInitResult res = new UploadInitResult();
        res.s3Key = s3Key;

        // ── ALL CALLOUTS FIRST — before any DML ────────────────────────
        // Salesforce rule: callouts cannot follow DML in the same transaction.
        // The S3 key is derived from intakeId + UUID so no record Id is needed yet.
        if (fileSize < MULTIPART_THRESHOLD) {
            // Single-part
            res.isMultipart = false;
            res.presignedUrl = S3LambdaService.presignPut(s3Key, contentType);
        } else {
            // Multipart
            res.isMultipart = true;
            String uploadId = S3LambdaService.multipartCreate(s3Key, contentType);
            res.uploadId = uploadId;

            Integer totalParts = (Integer) Math.ceil((Double) fileSize / MULTIPART_THRESHOLD);
            res.totalParts = totalParts;

            List<Integer> partNumbers = new List<Integer>();
            for (Integer i = 1; i <= totalParts; i++)
                partNumbers.add(i);
            res.partUrls = S3LambdaService.multipartPartBatch(s3Key, uploadId, partNumbers);
        }

        // ── SINGLE DML INSERT AFTER all callouts are done ──────────────
        Document__c record = new Document__c(
            Name = fileName,
            Folder__c = folderId,
            Intake__c = intakeId,
            S3_Key__c = s3Key,
            File_Size__c = fileSize,
            MIME_Type__c = contentType,
            Status__c = 'Pending Upload',
            Upload_Id__c = res.isMultipart ? res.uploadId : null
        );
        insert record;

        res.fileRecordId = record.Id;
        return res;
    }

    // ── Complete single-part upload ────────────────────────────────
    public static void completeSingleUpload(Id fileRecordId) {
        update new Document__c(Id = fileRecordId, Status__c = 'Active', Upload_Id__c = null);
    }

    // ── Complete multipart upload ──────────────────────────────────
    public static void completeMultipartUpload(
        Id fileRecordId,
        String s3Key,
        String uploadId,
        List<Map<String, Object>> parts
    ) {
        S3LambdaService.multipartComplete(s3Key, uploadId, parts);
        update new Document__c(Id = fileRecordId, Status__c = 'Active', Upload_Id__c = null);
    }

    // ── Abort failed upload ────────────────────────────────────────
    public static void abortUpload(Id fileRecordId, String s3Key, String uploadId) {
        try {
            S3LambdaService.multipartAbort(s3Key, uploadId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Abort failed: ' + e.getMessage());
        }
        update new Document__c(Id = fileRecordId, Status__c = 'Failed');
    }

    // ── Get download URL ───────────────────────────────────────────
    public static String getDownloadUrl(Id fileRecordId) {
        Document__c f = [SELECT S3_Key__c, Name FROM Document__c WHERE Id = :fileRecordId LIMIT 1];
        return S3LambdaService.presignGet(f.S3_Key__c, f.Name);
    }

    // ── Rename ─────────────────────────────────────────────────────
    public static void renameFile(Id fileRecordId, String newName) {
        update new Document__c(Id = fileRecordId, Name = newName.trim());
    }

    // ── Soft delete ────────────────────────────────────────────────
    public static void deleteFile(Id fileRecordId) {
        Document__c f = [SELECT Id, S3_Key__c FROM Document__c WHERE Id = :fileRecordId LIMIT 1];
        f.Status__c = 'Deleted';
        update f;
        deleteS3Async(f.S3_Key__c);
    }

    @future(callout=true)
    private static void deleteS3Async(String s3Key) {
        try {
            S3LambdaService.deleteObject(s3Key);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'S3 delete failed: ' + e.getMessage());
        }
    }

    private static FileDTO toDTO(Document__c f) {
        FileDTO d = new FileDTO();
        d.id = f.Id;
        d.name = f.Name;
        d.s3Key = f.S3_Key__c;
        d.fileSize = f.File_Size__c != null ? (Long) f.File_Size__c : 0;
        d.mimeType = f.MIME_Type__c;
        d.status = f.Status__c;
        d.description = f.Notes__c;
        d.createdDate = f.CreatedDate != null ? f.CreatedDate.format('MMM d, yyyy') : '';
        d.createdBy = f.CreatedBy?.Name ?? '';
        d.uploadId = f.Upload_Id__c;
        return d;
    }
}