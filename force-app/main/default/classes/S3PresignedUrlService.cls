public with sharing class S3PresignedUrlService {
    @AuraEnabled
    public static String getUploadUrl(String fileName, Id intakeId) {
        String key = 'Intake/' + intakeId + '/' + fileName;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'https://fpxbao3eq1.execute-api.us-east-1.amazonaws.com/prod/upload-url?key=' +
            EncodingUtil.urlEncode(key, 'UTF-8')
        );
        req.setMethod('GET');

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug(res.getBody());

        return res.getBody();
    }

    @AuraEnabled
    public static String createDocument(String fileName, String s3Key, Id intakeId) {
        String fileUrl = 'https://legal-intake-documents.s3.amazonaws.com/' + s3Key;

        Document__c doc = new Document__c(
            Name = fileName,
            File_URL__c = fileUrl,
            S3_Key__c = s3Key,
            Intake__c = intakeId
        );

        insert doc;
        return fileUrl;
    }
}
