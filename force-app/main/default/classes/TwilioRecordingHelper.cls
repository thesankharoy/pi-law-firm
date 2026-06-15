public without sharing class TwilioRecordingHelper {

    public static void attachRecording(Id taskId, String recordingUrl) {
        if (String.isBlank(recordingUrl)) {
            System.debug('No recording URL provided, skipping attachment.');
            return;
        }

        Twilio_Config__mdt cfg = Twilio_Config__mdt.getInstance('Default');

        if (cfg == null || String.isBlank(cfg.Account_SID__c) || String.isBlank(cfg.Auth_Token__c)) {
            System.debug('Twilio_Config__mdt not configured, skipping attachment.');
            return;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(recordingUrl + '.mp3');
        req.setMethod('GET');
        req.setHeader(
            'Authorization',
            'Basic ' + EncodingUtil.base64Encode(
                Blob.valueOf(cfg.Account_SID__c + ':' + cfg.Auth_Token__c)
            )
        );

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            ContentVersion cv = new ContentVersion();
            cv.Title = 'Call Recording - ' + taskId;
            cv.PathOnClient = taskId + '.mp3';
            cv.VersionData = res.getBodyAsBlob();
            cv.FirstPublishLocationId = taskId;
            insert cv;
        } else {
            System.debug('Recording download failed: ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }
}