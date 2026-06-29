public without sharing class TwilioRecordingHelper {

    // Called from webhook - runs async to avoid callout-after-DML error
    @future(callout=true)
    public static void attachRecordingAsync(Id taskId, String recordingUrl) {
        attachRecording(taskId, recordingUrl);
    }

    public static void attachRecording(Id taskId, String recordingUrl) {
        if (String.isBlank(recordingUrl)) return;

        Twilio_Config__mdt cfg = Twilio_Config__mdt.getInstance('Default');
        if (cfg == null || String.isBlank(cfg.Account_SID__c) || String.isBlank(cfg.Auth_Token__c)) return;

        // ── Get WhatId from Task ──────────────────────────────────
        Task t = [SELECT Id, WhatId FROM Task WHERE Id = :taskId LIMIT 1];
        Id publishLocation = (t.WhatId != null) ? t.WhatId : taskId;
        // ─────────────────────────────────────────────────────────

        HttpRequest req = new HttpRequest();
        req.setEndpoint(recordingUrl);
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
            blob body = res.getBodyAsBlob();

            // ── Guard against heap limit (12MB async limit) ───────────
            if (body.size() > 10000000) {
                System.debug('Recording too large to attach as file: ' + body.size() + ' bytes. Skipping file attachment.');
                return;
            }
            // ─────────────────────────────────────────────────────────

            ContentVersion cv = new ContentVersion();
            cv.Title           = 'Call Recording - ' + taskId;
            cv.PathOnClient    = 'CallRecording_' + taskId + '.mp3';
            cv.VersionData     = body;
            cv.FirstPublishLocationId = publishLocation;
            insert cv;
        } else {
            System.debug('Recording download failed: ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }
}