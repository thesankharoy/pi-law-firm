@RestResource(urlMapping='/twilio/contact-check')
global without sharing class TwilioContactCheck {

    @HttpGet
    global static void handleGet() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        String phone = req.params.get('phone');

        if (String.isBlank(phone)) {
            res.statusCode   = 400;
            res.responseBody = Blob.valueOf('{"error":"Missing phone"}');
            return;
        }

        List<Contact> contacts = [
            SELECT Id, FirstName
            FROM Contact
            WHERE MobilePhone = :phone OR Phone = :phone
            LIMIT 1
        ];

        if (contacts.isEmpty()) {
            res.statusCode   = 200;
            res.responseBody = Blob.valueOf('{"found":false}');
        } else {
            res.statusCode   = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'found'     => true,
                'contactId' => contacts[0].Id,
                'firstName' => contacts[0].FirstName
            }));
        }
    }
}