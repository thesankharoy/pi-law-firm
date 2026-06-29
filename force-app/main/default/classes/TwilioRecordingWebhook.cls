@RestResource(urlMapping='/twilio/recording')
global without sharing class TwilioRecordingWebhook {

    @HttpPost
    global static void handlePost() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        String callSid           = req.params.get('CallSid');
        String recordingSid      = req.params.get('RecordingSid');
        String recordingUrl      = req.params.get('RecordingUrl');     // legacy Twilio URL (reference only)
        String recordingS3Key    = req.params.get('RecordingS3Key');   // playback source (S3)
        String recordingDuration = req.params.get('RecordingDuration');

        if (String.isBlank(callSid)) { res.statusCode = 400; return; }

        // Reconcile on CallObject — the SAME key TwilioCallLogWebhook and the
        // transcription webhook use. Previously this matched on Call_SID__c, which
        // call-log never sets, so recordings landed on orphan "Twilio Call" tasks.
        List<Task> tasks = [SELECT Id FROM Task WHERE CallObject = :callSid LIMIT 1];

        if (tasks.isEmpty()) {
            // Do NOT create a new task (that orphaning was the original bug).
            // 404 so Twilio retries — covers the rare case the recording callback
            // beats the call-log webhook.
            res.statusCode   = 404;
            res.responseBody = Blob.valueOf('No Task for CallSid ' + callSid);
            return;
        }

        Task t = tasks[0];
        t.Call_SID__c      = callSid;
        t.Recording_SID__c = recordingSid;
        if (String.isNotBlank(recordingUrl))   t.Recording_URL__c     = recordingUrl;
        if (String.isNotBlank(recordingS3Key)) t.Recording_S3_Key__c  = recordingS3Key;
        if (String.isNotBlank(recordingDuration) && recordingDuration.isNumeric()) {
            t.CallDurationInSeconds = Integer.valueOf(recordingDuration);
        }

        try {
            update t;
            res.statusCode   = 200;
            res.responseBody = Blob.valueOf('OK');
        } catch (Exception e) {
            res.statusCode   = 500;
            res.responseBody = Blob.valueOf('ERROR: ' + e.getMessage());
            System.debug('TwilioRecordingWebhook error: ' + e.getMessage());
        }
    }
}