@RestResource(urlMapping='/twilio/callstart')
global without sharing class TwilioCallStart {

    @HttpPost
    global static void handlePost() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        String callSid  = req.params.get('CallSid');
        String toNumber = req.params.get('To');
        String intakeId = req.params.get('IntakeId');

        if (String.isBlank(callSid) && req.requestBody != null) {
            Map<String, String> bodyParams = parseFormBody(req.requestBody.toString());
            callSid  = bodyParams.get('CallSid');
            toNumber = bodyParams.get('To');
            intakeId = bodyParams.get('IntakeId');
        }

        if (String.isBlank(callSid)) {
            res.statusCode   = 400;
            res.responseBody = Blob.valueOf('Missing CallSid');
            return;
        }

        // Dedupe by CallObject (standard field — matches TwilioTranscriptionWebhook lookup)
        List<Task> existing = [SELECT Id FROM Task WHERE CallObject = :callSid LIMIT 1];
        if (!existing.isEmpty()) {
            res.statusCode   = 200;
            res.responseBody = Blob.valueOf('Already exists');
            return;
        }

        Task t         = new Task();
        t.CallObject   = callSid;   // standard field — used by TwilioTranscriptionWebhook
        t.Subject      = 'Outbound Call to ' + toNumber;
        t.CallType     = 'Outbound';
        t.CallDisposition = 'Answered';
        t.Status       = 'Completed';
        t.ActivityDate = System.today();
        // t.TaskSubtype = 'Call';  ← removed: causes 500 in Salesforce REST API

        if (String.isNotBlank(intakeId)) {
            try {
                t.WhatId = (Id) intakeId;
            } catch (Exception e) {
                System.debug('Invalid IntakeId: ' + intakeId + ' | ' + e.getMessage());
            }
        }

        // Look up Contact by the number being dialled
        if (String.isNotBlank(toNumber)) {
            List<Contact> contacts = [
                SELECT Id FROM Contact
                WHERE MobilePhone = :toNumber OR Phone = :toNumber
                LIMIT 1
            ];
            if (!contacts.isEmpty()) t.WhoId = contacts[0].Id;
        }

        insert t;

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