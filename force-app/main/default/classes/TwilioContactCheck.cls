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

        Set<String> variants = phoneVariants(phone);
        List<Contact> contacts = [
            SELECT Id, FirstName
            FROM Contact
            WHERE MobilePhone IN :variants OR Phone IN :variants
            LIMIT 1
        ];

        if (contacts.isEmpty()) {
            res.statusCode   = 200;
            res.responseBody = Blob.valueOf('{"found":false}');
            return;
        }

        String contactId = contacts[0].Id;

        // Active intake = an Intake__c record exists that is NOT closed/rejected
        List<Intake__c> activeIntakes = [
            SELECT Id FROM Intake__c
            WHERE Client__c = :contactId
            AND Status__c NOT IN ('Turned Down', 'Referred Out', 'Converted')
            LIMIT 1
        ];
        Boolean hasActiveIntake = !activeIntakes.isEmpty();

        res.statusCode   = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'found'           => true,
            'contactId'       => contactId,
            'firstName'       => contacts[0].FirstName,
            'hasActiveIntake' => hasActiveIntake
        }));
    }

    private static Set<String> phoneVariants(String phone) {
        Set<String> v = new Set<String>();
        v.add(phone);
        String digits = phone.replaceAll('[^0-9]', '');
        v.add(digits);
        String ten = digits.length() == 11 && digits.startsWith('1') ? digits.substring(1) : digits;
        if (ten.length() == 10) {
            v.add(ten);
            v.add('+1' + ten);
            v.add('1' + ten);
            v.add('(' + ten.substring(0,3) + ') ' + ten.substring(3,6) + '-' + ten.substring(6));
            v.add(ten.substring(0,3) + '-' + ten.substring(3,6) + '-' + ten.substring(6));
            v.add(ten.substring(0,3) + '.' + ten.substring(3,6) + '.' + ten.substring(6));
        }
        return v;
    }
}