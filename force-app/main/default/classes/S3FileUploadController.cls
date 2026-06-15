public with sharing class S3FileUploadController {

    @AuraEnabled
    public static String uploadFile(
        String fileName,
        String contentType,
        String base64Data,
        Id intakeId
    ) {
        try {

            System.debug('intakeId = ' + intakeId);
            System.debug('fileName = ' + fileName);
            System.debug('contentType = ' + contentType);

            if(String.isBlank(fileName)){
                throw new AuraHandledException('File name is required.');
            }

            if(String.isBlank(base64Data)){
                throw new AuraHandledException('File data is missing.');
            }

            String safeFileName =
                fileName.replaceAll('[^a-zA-Z0-9._-]', '_');

            Blob fileBody =
                EncodingUtil.base64Decode(base64Data);

            String key =
                'Intake/' +
                intakeId +
                '/' +
                safeFileName;

            HttpRequest req = new HttpRequest();

            req.setEndpoint(
                'callout:AWS_S3/' + key
            );

            req.setMethod('PUT');

            req.setHeader(
                'Content-Type',
                String.isBlank(contentType)
                    ? 'application/octet-stream'
                    : contentType
            );

            req.setHeader(
                'Content-Disposition',
                'inline'
            );

            req.setBodyAsBlob(fileBody);

            Http http = new Http();

            HttpResponse res = http.send(req);

            System.debug('Status Code = ' + res.getStatusCode());
            System.debug('Response = ' + res.getBody());

            if (
                res.getStatusCode() != 200 &&
                res.getStatusCode() != 201
            ) {
                throw new AuraHandledException(
                    'Upload Failed : ' +
                    res.getStatusCode() +
                    ' - ' +
                    res.getBody()
                );
            }

            String fileUrl =
                'https://legal-intake-documents.s3.amazonaws.com/'
                + key;

            Document__c doc = new Document__c(
                Name = fileName,
                File_URL__c = fileUrl,
                S3_Key__c = key,
                Intake__c = intakeId
            );

            insert doc;

            return fileUrl;

        } catch (Exception ex) {

            System.debug('ERROR = ' + ex.getMessage());
            System.debug('STACK = ' + ex.getStackTraceString());

            throw new AuraHandledException(
                ex.getMessage()
            );
        }
    }
    
    
    @AuraEnabled(cacheable=true)
public static List<Document__c> getDocuments(Id intakeId) {

    return [
        SELECT Id,
               Name,
               File_URL__c,
               S3_Key__c,
               CreatedDate
        FROM Document__c
        WHERE Intake__c = :intakeId
        ORDER BY CreatedDate DESC
    ];
}
    
    
    
    @AuraEnabled
public static void deleteDocument(Id documentId) {

    try {

        Document__c doc = [
            SELECT Id,
                   Name,
                   S3_Key__c
            FROM Document__c
            WHERE Id = :documentId
            LIMIT 1
        ];

        HttpRequest req = new HttpRequest();

        req.setEndpoint(
            'callout:AWS_S3/' + doc.S3_Key__c
        );

        req.setMethod('DELETE');

        Http http = new Http();

        HttpResponse res = http.send(req);

        System.debug('Delete Status: ' + res.getStatusCode());

        if(
            res.getStatusCode() != 200 &&
            res.getStatusCode() != 204
        ){
            throw new AuraHandledException(
                'Failed to delete file from S3. Status: '
                + res.getStatusCode()
            );
        }

        delete doc;

    } catch(Exception ex) {

        throw new AuraHandledException(
            ex.getMessage()
        );
    }
}
}