@RestResource(urlMapping='/twilio/returning-caller')
global without sharing class TwilioReturningCallerWebhook {

    @HttpPost
    global static void handlePost() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        String contactId = req.params.get('ContactId');
        String reason    = req.params.get('Reason');
        String isUrgent  = req.params.get('IsUrgent');
        String phone     = req.params.get('Phone');

        if (String.isBlank(contactId) && req.requestBody != null) {
            Map<String, String> body = parseFormBody(req.requestBody.toString());
            contactId = body.get('ContactId');
            reason    = body.get('Reason');
            isUrgent  = body.get('IsUrgent');
            phone     = body.get('Phone');
        }

        if (String.isBlank(contactId)) {
            res.statusCode   = 400;
            res.responseBody = Blob.valueOf('Missing ContactId');
            return;
        }

        try {
            Contact c = [SELECT Id, Name, FirstName, OwnerId FROM Contact WHERE Id = :contactId LIMIT 1];

            Boolean urgent = String.isNotBlank(isUrgent) && isUrgent.toLowerCase().contains('yes');

            // Create Case (ticket)
            Case newCase        = new Case();
            newCase.ContactId   = c.Id;
            newCase.Subject     = 'Returning Caller — ' + (String.isNotBlank(reason) ? reason.abbreviate(80) : 'No reason given');
            newCase.Description = reason;
            newCase.Priority    = urgent ? 'High' : 'Medium';
            newCase.Status      = 'New';
            newCase.Origin      = 'Phone';
            newCase.OwnerId     = c.OwnerId;
            insert newCase;

            // Create follow-up Task assigned to Contact owner
            Task t         = new Task();
            t.Subject      = (urgent ? '[URGENT] ' : '') + 'Returning caller: ' + c.Name;
            t.WhoId        = c.Id;
            t.WhatId       = newCase.Id;
            t.OwnerId      = c.OwnerId;
            t.ActivityDate = Date.today();
            t.Status       = 'Not Started';
            t.Priority     = urgent ? 'High' : 'Normal';
            t.Description  = 'Called from ' + phone + '\nReason: ' + reason +
                             (urgent ? '\n⚠️ URGENT' : '');
            insert t;

            // Chatter post on Contact so team sees it immediately
            FeedItem post = new FeedItem();
            post.ParentId = c.Id;
            post.Body     = '📞 ' + c.Name + ' called and left a message:\n\n"' + reason + '"' +
                            (urgent ? '\n\n⚠️ Marked as URGENT' : '') +
                            '\n\nCase ' + newCase.CaseNumber + ' created and assigned to owner.';
            insert post;

            res.statusCode   = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'status'     => 'success',
                'caseId'     => newCase.Id,
                'caseNumber' => newCase.CaseNumber,
                'taskId'     => t.Id
            }));

        } catch (Exception e) {
            res.statusCode   = 500;
            res.responseBody = Blob.valueOf('ERROR: ' + e.getMessage());
            System.debug('TwilioReturningCallerWebhook error: ' + e.getMessage());
        }
    }

    private static Map<String, String> parseFormBody(String body) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(body)) return result;
        for (String pair : body.split('&')) {
            List<String> kv = pair.split('=', 2);
            if (kv.size() == 2) {
                result.put(EncodingUtil.urlDecode(kv[0], 'UTF-8'), EncodingUtil.urlDecode(kv[1], 'UTF-8'));
            }
        }
        return result;
    }
}