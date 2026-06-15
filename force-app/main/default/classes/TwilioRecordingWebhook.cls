@RestResource(urlMapping='/twilio/recording/*')
global without sharing class TwilioRecordingWebhook {

    @HttpPost
    global static void handleRecording() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String body = req.requestBody.toString();
        Map<String, String> params = parseFormBody(body);

        String callSid = params.get('CallSid');
        String recordingSid = params.get('RecordingSid');
        String recordingUrl = params.get('RecordingUrl');
        String durationStr = params.get('RecordingDuration');

        System.debug('===== TWILIO RECORDING CALLBACK =====');
        System.debug('CallSid=' + callSid);
        System.debug('RecordingSid=' + recordingSid);
        System.debug('RecordingUrl=' + recordingUrl);
        System.debug('Duration=' + durationStr);

        if (String.isBlank(callSid)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('Missing CallSid');
            return;
        }

        Task t;
        List<Task> existing = [
            SELECT Id FROM Task WHERE Call_Sid__c = :callSid LIMIT 1
        ];

        if (!existing.isEmpty()) {
            t = existing[0];
        } else {
            // Fallback: callstart webhook may not have fired
            t = new Task();
            t.Call_Sid__c = callSid;
            t.Subject = 'Twilio Call';
            t.ActivityDate = System.today();
            t.TaskSubtype = 'Call';
        }

        t.Recording_Url__c = recordingUrl;
        t.CallDurationInSeconds = String.isBlank(durationStr) ? null : Integer.valueOf(durationStr);
        t.Status = 'Completed';

        upsert t;

        TwilioRecordingHelper.attachRecording(t.Id, recordingUrl);

        res.statusCode = 200;
        res.responseBody = Blob.valueOf('OK');
    }

    private static Map<String, String> parseFormBody(String body) {
        Map<String, String> result = new Map<String, String>();
        for (String pair : body.split('&')) {
            List<String> kv = pair.split('=', 2);
            if (kv.size() == 2) {
                result.put(
                    EncodingUtil.urlDecode(kv[0], 'UTF-8'),
                    EncodingUtil.urlDecode(kv[1], 'UTF-8')
                );
            }
        }
        return result;
    }
}