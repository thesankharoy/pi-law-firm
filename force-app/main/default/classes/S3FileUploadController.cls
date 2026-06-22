public with sharing class S3FileUploadController {
    @AuraEnabled(cacheable=true)
    public static List<Document__c> getDocuments(Id intakeId) {
        return [
            SELECT Id, Name, File_URL__c, S3_Key__c, CreatedDate
            FROM Document__c
            WHERE Intake__c = :intakeId
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled
    public static void deleteDocument(Id documentId) {
        try {
            Document__c doc = [
                SELECT Id, Name, S3_Key__c
                FROM Document__c
                WHERE Id = :documentId
                LIMIT 1
            ];

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:AWS_S3/' + doc.S3_Key__c);
            req.setMethod('DELETE');

            Http http = new Http();
            HttpResponse res = http.send(req);

            System.debug('Delete Status: ' + res.getStatusCode());

            if (res.getStatusCode() != 200 && res.getStatusCode() != 204) {
                throw new AuraHandledException('Failed to delete file from S3. Status: ' + res.getStatusCode());
            }

            delete doc;
        } catch (Exception ex) {
            System.debug('DELETE ERROR = ' + ex.getMessage());
            System.debug('STACK = ' + ex.getStackTraceString());

            throw new AuraHandledException(ex.getMessage());
        }
    }
}
