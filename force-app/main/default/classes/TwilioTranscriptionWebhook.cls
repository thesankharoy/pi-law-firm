@RestResource(urlMapping='/twilio/transcription')
global without sharing class TwilioTranscriptionWebhook {

    @HttpPost
    global static void handleTranscription() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        String callSid           = req.params.get('CallSid');
        String transcriptSid     = req.params.get('TranscriptSid');
        String transcriptionText = req.params.get('TranscriptionText');

        if (String.isBlank(callSid) && req.requestBody != null) {
            Map<String, String> body = parseFormBody(req.requestBody.toString());
            callSid           = body.get('CallSid');
            transcriptSid     = body.get('TranscriptSid');
            transcriptionText = body.get('TranscriptionText');
        }

        System.debug('===== TWILIO TRANSCRIPTION =====');
        System.debug('CallSid='           + callSid);
        System.debug('TranscriptSid='     + transcriptSid);
        System.debug('TranscriptionText=' + transcriptionText);

        if (String.isBlank(callSid) && String.isBlank(transcriptSid)) {
            res.statusCode   = 400;
            res.responseBody = Blob.valueOf('Missing CallSid or TranscriptSid');
            return;
        }

        // Lookup Task by CallObject (standard field used by TwilioCallLogWebhook)
        List<Task> tasks = new List<Task>();

        if (String.isNotBlank(callSid)) {
            tasks = [SELECT Id FROM Task WHERE CallObject = :callSid LIMIT 1];
        }

        if (tasks.isEmpty() && String.isNotBlank(transcriptSid)) {
            tasks = [SELECT Id FROM Task WHERE Transcript_SID__c = :transcriptSid LIMIT 1];
        }

        if (tasks.isEmpty()) {
            res.statusCode   = 404;
            res.responseBody = Blob.valueOf('Task not found for CallSid: ' + callSid);
            return;
        }

        Task t        = tasks[0];
        t.Description = transcriptionText;
        if (String.isNotBlank(transcriptSid)) {
            t.Transcript_SID__c = transcriptSid;
        }
        update t;

        System.debug('Task updated with transcription: ' + t.Id);

        res.statusCode   = 200;
        res.responseBody = Blob.valueOf('OK');
    }

    private static Map<String, String> parseFormBody(String body) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(body)) return result;
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