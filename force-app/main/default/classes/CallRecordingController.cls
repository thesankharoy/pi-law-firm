public with sharing class CallRecordingController {

    // Named Credential pointing at the dedicated recordings presign Lambda
    // (Function URL). Kept separate from the document DMS Lambda on purpose.
    private static final String PRESIGN_ENDPOINT = 'callout:Recordings_Lambda';

    // Returns a short-lived presigned GET URL for the recording on the given Task,
    // or null if no recording is attached.
    @AuraEnabled(cacheable=false)
    public static String getRecordingUrl(Id recordId) {
        if (recordId == null) return null;

        Task t = [
            SELECT Id, Subject, Recording_S3_Key__c
            FROM Task
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (String.isBlank(t.Recording_S3_Key__c)) return null;

        String fileName = String.isBlank(t.Subject) ? 'recording.mp3' : t.Subject + '.mp3';
        return presignGet(t.Recording_S3_Key__c, fileName);
    }

    // Calls the recordings Lambda for a short-lived GET URL (15-min default expiry).
    private static String presignGet(String key, String fileName) {
        Recording_Config__c cfg = Recording_Config__c.getOrgDefaults();
        String apiKey = (cfg != null) ? cfg.Api_Key__c : null;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(PRESIGN_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Api-Key', apiKey);
        req.setBody(JSON.serialize(new Map<String, Object>{
            'action'   => 'get',
            'key'      => key,
            'fileName' => fileName
        }));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException(
                'Recording presign failed (' + res.getStatusCode() + ')'
            );
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) body.get('url');
    }
}