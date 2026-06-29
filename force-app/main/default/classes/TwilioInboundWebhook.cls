@RestResource(urlMapping='/twilio/inbound')
global without sharing class TwilioInboundWebhook {

    @HttpPost
    global static void handleInbound() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            String firstName     = '';
            String lastName      = '';
            String email         = '';
            String phone         = '';
            String intakeSummary = '';

            String body = req.requestBody != null ? req.requestBody.toString() : '';
            if (String.isNotBlank(body) && body.trim().startsWith('{')) {
                Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(body);
                firstName     = getString(data, 'firstName');
                lastName      = getString(data, 'lastName');
                email         = getString(data, 'email');
                phone         = getString(data, 'phone');
                intakeSummary = getString(data, 'intakeSummary');
            } else {
                firstName     = req.params.get('firstName')     != null ? req.params.get('firstName')     : '';
                lastName      = req.params.get('lastName')      != null ? req.params.get('lastName')      : '';
                email         = req.params.get('email')         != null ? req.params.get('email')         : '';
                phone         = req.params.get('phone')         != null ? req.params.get('phone')         : '';
                intakeSummary = req.params.get('intakeSummary') != null ? req.params.get('intakeSummary') : '';
            }

            // Dedup: look up existing Contact by phone before creating
            List<Contact> existing = String.isNotBlank(phone)
                ? [SELECT Id FROM Contact WHERE MobilePhone = :phone OR Phone = :phone LIMIT 1]
                : new List<Contact>();

            Contact c;
            Boolean isNew = existing.isEmpty();

            if (isNew) {
                c = new Contact();
                c.FirstName   = String.isBlank(firstName) ? 'Unknown' : firstName;
                c.LastName    = String.isBlank(lastName)  ? 'Caller'  : lastName;
                if (String.isNotBlank(phone)) c.MobilePhone = phone;
            } else {
                c = existing[0];
            }

            // Always update intake summary and email on both new and existing
            c.Intake_Summary__c = intakeSummary;
            if (String.isNotBlank(email) && email.contains('@')) c.Email = email;

            if (isNew) {
                insert c;
            } else {
                update c;
            }

            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
                'status'    => 'success',
                'contactId' => c.Id,
                'action'    => isNew ? 'created' : 'updated'
            }));

        } catch (Exception e) {
            res.statusCode = 500;
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