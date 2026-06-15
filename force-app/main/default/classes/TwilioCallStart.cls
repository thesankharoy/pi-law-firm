@RestResource(urlMapping='/twilio/callstart')
global without sharing class TwilioCallStart {

    @HttpPost
    global static void handlePost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String body = req.requestBody.toString();
        Map<String, String> params = parseFormBody(body);

        String callSid = params.get('CallSid');
        String toNumber = params.get('To');
        String intakeId = params.get('IntakeId');

        System.debug('===== TWILIO CALL START =====');
        System.debug('CallSid=' + callSid);
        System.debug('To=' + toNumber);
        System.debug('IntakeId=' + intakeId);

        if (String.isBlank(callSid)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('Missing CallSid');
            return;
        }

        // Avoid duplicate Task if callstart fires more than once for same CallSid
        List<Task> existing = [
            SELECT Id FROM Task WHERE Call_Sid__c = :callSid LIMIT 1
        ];

        if (!existing.isEmpty()) {
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('Already exists');
            return;
        }

        Task t = new Task();
        t.Call_Sid__c = callSid;
        t.Subject = 'Twilio Call to ' + toNumber;
        t.Status = 'In Progress';
        t.ActivityDate = System.today();
        t.TaskSubtype = 'Call';

        if (!String.isBlank(intakeId)) {
            try {
                t.WhatId = (Id) intakeId;
            } catch (Exception e) {
                System.debug('Invalid IntakeId received: ' + intakeId + ' | ' + e.getMessage());
            }
        }

        insert t;

        res.statusCode = 200;
        res.responseBody = Blob.valueOf('OK');
    }

    private static Map<String, String> parseFormBody(String body) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(body)) {
            return result;
        }
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