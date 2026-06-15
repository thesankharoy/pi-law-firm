public with sharing class TwilioTokenService {

    @AuraEnabled
    public static String getToken() {

        HttpRequest req = new HttpRequest();

        req.setEndpoint(
            'https://salesforce-softphone-9217.twil.io/token'
        );

        req.setMethod('GET');

        Http http = new Http();

        HttpResponse res = http.send(req);

        System.debug(res.getBody());

        return res.getBody();
    }
}