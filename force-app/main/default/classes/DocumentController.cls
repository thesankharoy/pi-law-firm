public with sharing class DocumentController {
    // ── Bootstrap: get or create root folder ───────────────────────
    @AuraEnabled
    public static Map<String, Object> initDMS(Id intakeId) {
        Folder__c root = DocumentFolderService.ensureRoot(intakeId);
        return new Map<String, Object>{ 'rootFolderId' => root.Id, 'rootPath' => root.Path__c };
    }

    // ── Folder operations ──────────────────────────────────────────
    @AuraEnabled
    public static List<DocumentFolderService.FolderDTO> listFolders(Id parentFolderId) {
        return DocumentFolderService.listFolders(parentFolderId);
    }

    @AuraEnabled
    public static DocumentFolderService.FolderDTO createFolder(Id intakeId, Id parentFolderId, String name) {
        return DocumentFolderService.createFolder(intakeId, parentFolderId, name);
    }

    @AuraEnabled
    public static void renameFolder(Id folderId, String newName) {
        DocumentFolderService.renameFolder(folderId, newName);
    }

    @AuraEnabled
    public static void deleteFolder(Id folderId) {
        DocumentFolderService.deleteFolder(folderId);
    }

    @AuraEnabled
    public static List<DocumentFolderService.FolderDTO> getBreadcrumb(Id folderId) {
        return DocumentFolderService.breadcrumb(folderId);
    }

    // ── File operations ────────────────────────────────────────────
    @AuraEnabled
    public static List<DocumentFileService.FileDTO> listFiles(Id folderId) {
        return DocumentFileService.listFiles(folderId);
    }

    @AuraEnabled
    public static DocumentFileService.UploadInitResult initiateUpload(
        Id intakeId,
        Id folderId,
        String fileName,
        Long fileSize,
        String contentType
    ) {
        return DocumentFileService.initiateUpload(intakeId, folderId, fileName, fileSize, contentType);
    }

    @AuraEnabled
    public static void completeSingleUpload(Id fileRecordId) {
        DocumentFileService.completeSingleUpload(fileRecordId);
    }

    @AuraEnabled
    public static void completeMultipartUpload(Id fileRecordId, String s3Key, String uploadId, String partsJson) {
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(partsJson);
        List<Map<String, Object>> parts = new List<Map<String, Object>>();
        for (Object o : raw)
            parts.add((Map<String, Object>) o);
        DocumentFileService.completeMultipartUpload(fileRecordId, s3Key, uploadId, parts);
    }

    @AuraEnabled
    public static void abortUpload(Id fileRecordId, String s3Key, String uploadId) {
        DocumentFileService.abortUpload(fileRecordId, s3Key, uploadId);
    }

    @AuraEnabled
    public static String getDownloadUrl(Id fileRecordId) {
        return DocumentFileService.getDownloadUrl(fileRecordId);
    }

    @AuraEnabled
    public static String getViewUrl(Id fileRecordId) {
        Document__c f = [SELECT S3_Key__c FROM Document__c WHERE Id = :fileRecordId LIMIT 1];
        return S3LambdaService.presignView(f.S3_Key__c);
    }

    @AuraEnabled
    public static void renameFile(Id fileRecordId, String newName) {
        DocumentFileService.renameFile(fileRecordId, newName);
    }

    @AuraEnabled
    public static void deleteFile(Id fileRecordId) {
        DocumentFileService.deleteFile(fileRecordId);
    }

    // ── Search across an entire intake's files ─────────────────────
    @AuraEnabled
    public static List<DocumentFileService.FileDTO> searchFiles(Id intakeId, String query) {
        List<DocumentFileService.FileDTO> results = new List<DocumentFileService.FileDTO>();
        String q = '%' + query.trim() + '%';
        for (Document__c f : [
            SELECT Id, Name, S3_Key__c, File_Size__c, MIME_Type__c, Status__c, Notes__c, CreatedDate, CreatedBy.Name
            FROM Document__c
            WHERE Intake__c = :intakeId AND Status__c != 'Deleted' AND Name LIKE :q
            ORDER BY Name ASC
            LIMIT 50
        ]) {
            DocumentFileService.FileDTO d = new DocumentFileService.FileDTO();
            d.id = f.Id;
            d.name = f.Name;
            d.s3Key = f.S3_Key__c;
            d.fileSize = f.File_Size__c != null ? (Long) f.File_Size__c : 0;
            d.mimeType = f.MIME_Type__c;
            d.status = f.Status__c;
            d.description = f.Notes__c;
            d.createdDate = f.CreatedDate != null ? f.CreatedDate.format('MMM d, yyyy') : '';
            d.createdBy = f.CreatedBy?.Name ?? '';
            results.add(d);
        }
        return results;
    }
}
