@RestResource(urlMapping='/twilio/call-log/*')
global without sharing class TwilioCallLogWebhook {

    @HttpPost
    global static void handlePost() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        String callSid    = req.params.get('CallSid');
        String fro        = req.params.get('From');
        String callStatus = req.params.get('CallStatus');
        String answerTime = req.params.get('AnswerTimeSeconds');
        String duration   = req.params.get('CallDuration');
        String incomingTs = req.params.get('IncomingTs');

        if (String.isBlank(callSid)) { res.statusCode = 400; return; }

        if (callStatus != 'in-progress' && callStatus != 'no-answer' &&
            callStatus != 'busy'        && callStatus != 'canceled') {
            res.statusCode = 200; return;
        }

        Boolean answered = (callStatus == 'in-progress');

        // LINK TO AN EXISTING CONTACT ONLY — never create here. The AI call
        // assistant creates the Contact with the real captured name.
        Id contactId = findContactIdByPhone(fro);
        Id intakeId  = (contactId != null) ? findRelatedIntakeId(contactId) : null;

        List<Task> existing = [SELECT Id FROM Task WHERE CallObject = :callSid LIMIT 1];
        Task t = existing.isEmpty() ? new Task() : existing[0];
        t.Subject      = 'Inbound Call from ' + fro;
        t.CallObject   = callSid;
        t.CallType     = 'Inbound';
        t.ActivityDate = Date.today();
        t.Status       = 'Completed';

        if (contactId != null) t.WhoId  = contactId;
        if (intakeId  != null) t.WhatId = intakeId;

        if (String.isNotBlank(incomingTs)) {
            t.Incoming_Time__c = DateTime.newInstance(Long.valueOf(incomingTs));
        }

        if (answered) {
            t.CallDisposition = 'Answered';
            if (String.isNotBlank(answerTime) && answerTime.isNumeric()) {
                t.Answer_Time_Seconds__c = Decimal.valueOf(answerTime);
            }
        } else {
            t.CallDisposition = 'Missed';
        }

        if (String.isNotBlank(duration) && duration.isNumeric()) {
            t.CallDurationInSeconds = Integer.valueOf(duration);
        }

        try {
            if (existing.isEmpty()) { insert t; } else { update t; }
            res.statusCode   = 200;
            res.responseBody = Blob.valueOf('OK');
        } catch (Exception e) {
            res.statusCode   = 500;
            res.responseBody = Blob.valueOf('ERROR: ' + e.getMessage());
            System.debug('TwilioCallLogWebhook error: ' + e.getMessage());
        }
    }

    private static Id findContactIdByPhone(String phoneNumber) {
        if (String.isBlank(phoneNumber)) return null;
        String digits = phoneNumber.replaceAll('[^0-9]', '');
        if (digits.length() < 7) return null;
        String last10 = digits.length() >= 10 ? digits.substring(digits.length() - 10) : digits;
        String pat = '%' + last10;

        List<Contact> cons = [
            SELECT Id
            FROM Contact
            WHERE MobilePhone LIKE :pat OR Phone LIKE :pat
            LIMIT 1
        ];
        return cons.isEmpty() ? null : cons[0].Id;
    }

    private static Id findRelatedIntakeId(Id contactId) {
        if (contactId == null) return null;
        List<Intake__c> intakes = [
            SELECT Id, Status__c
            FROM Intake__c
            WHERE Client__c = :contactId
            ORDER BY CreatedDate DESC
        ];
        if (intakes.isEmpty()) return null;
        Set<String> closedStatuses = new Set<String>{ 'Turned Down', 'Referred Out', 'Converted' };
        for (Intake__c i : intakes) {
            if (!closedStatuses.contains(i.Status__c)) return i.Id;
        }
        return intakes[0].Id;
    }
}