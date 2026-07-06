@RestResource(urlMapping='/twilio/inbound')
global without sharing class TwilioInboundWebhook {

    @HttpPost
    global static void handleInbound() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            String contactId     = '';
            String firstName     = '';
            String lastName      = '';
            String email         = '';
            String phone         = '';
            String intakeSummary = '';

            String body = req.requestBody != null ? req.requestBody.toString() : '';
            if (String.isNotBlank(body) && body.trim().startsWith('{')) {
                Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(body);
                contactId     = getString(data, 'contactId');
                firstName     = getString(data, 'firstName');
                lastName      = getString(data, 'lastName');
                email         = getString(data, 'email');
                phone         = getString(data, 'phone');
                intakeSummary = getString(data, 'intakeSummary');
            } else {
                contactId     = req.params.get('contactId')     != null ? req.params.get('contactId')     : '';
                firstName     = req.params.get('firstName')     != null ? req.params.get('firstName')     : '';
                lastName      = req.params.get('lastName')      != null ? req.params.get('lastName')      : '';
                email         = req.params.get('email')         != null ? req.params.get('email')         : '';
                phone         = req.params.get('phone')         != null ? req.params.get('phone')         : '';
                intakeSummary = req.params.get('intakeSummary') != null ? req.params.get('intakeSummary') : '';
            }

            Contact c;
            Boolean isNew;

            if (String.isNotBlank(contactId)) {
                // Returning caller with no active intake — use existing Contact
                List<Contact> found = [SELECT Id FROM Contact WHERE Id = :contactId LIMIT 1];
                if (found.isEmpty()) {
                    res.statusCode   = 404;
                    res.responseBody = Blob.valueOf('{"status":"error","message":"Contact not found"}');
                    return;
                }
                c     = found[0];
                isNew = false;
            } else {
                // New caller — dedup by phone
                List<Contact> existing = String.isNotBlank(phone)
                    ? [SELECT Id FROM Contact WHERE MobilePhone = :phone OR Phone = :phone LIMIT 1]
                    : new List<Contact>();
                isNew = existing.isEmpty();
                if (isNew) {
                    c           = new Contact();
                    c.FirstName = String.isBlank(firstName) ? 'Unknown' : firstName;
                    c.LastName  = String.isBlank(lastName)  ? 'Caller'  : lastName;
                    if (String.isNotBlank(phone)) c.MobilePhone = phone;
                } else {
                    c = existing[0];
                }
            }

            c.Intake_Summary__c = intakeSummary;
            if (String.isNotBlank(email) && email.contains('@')) c.Email = email;

            if (isNew) { insert c; } else { update c; }

            // Always create a new Intake__c record so TwilioContactCheck
            // can reliably check status on future calls
            Intake__c intake    = new Intake__c();
            intake.Client__c   = c.Id;
            intake.Status__c    = 'New';
            insert intake;

            res.statusCode   = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'status'    => 'success',
                'contactId' => c.Id,
                'intakeId'  => intake.Id,
                'action'    => isNew ? 'created' : 'updated'
            }));

        } catch (Exception e) {
            res.statusCode   = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'status'  => 'error',
                'message' => e.getMessage()
            }));
        }
    }

    private static String getString(Map<String, Object> data, String key) {
        Object val = data.get(key);
        return val != null ? String.valueOf(val).trim() : '';
    }
}