global class TwilioTokenServiceVF {

    @RemoteAction
    global static String getToken() {

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://salesforce-softphone-9217.twil.io/token');
        req.setMethod('GET');

        Http http = new Http();
        HttpResponse res = http.send(req);

        String body = res.getBody();

        // Temporary debug — check Salesforce debug logs for this
        System.debug('TOKEN BODY: ' + body);
        System.debug('STATUS: ' + res.getStatusCode());

        return body;
    }
}