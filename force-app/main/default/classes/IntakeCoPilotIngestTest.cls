@isTest
private class IntakeCoPilotIngestTest {

    private static RestRequest buildRequest(String body) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/copilot/v1/turn';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        return req;
    }

    @isTest
    static void publishTurn_validPayload_returns202() {
        Contact c = new Contact(LastName = 'Caller');
        insert c;
        Intake__c intake = new Intake__c(Client__c = c.Id, Status__c = 'New');
        insert intake;

        String body = JSON.serialize(new Map<String, Object>{
            'intakeId' => intake.Id,
            'turnType' => 'client',
            'transcript' => 'Tuve un accidente.',
            'translation' => 'I had an accident.',
            'detectedLanguage' => 'es',
            'suggestion' => 'Ask about injuries and treatment.',
            'sentiment' => 'Negative',
            'leadFit' => 'Strong',
            'sequence' => 1
        });
        buildRequest(body);

        Test.startTest();
        IntakeCoPilotIngest.IngestResult r = IntakeCoPilotIngest.publishTurn();
        Test.stopTest();

        System.assertEquals(true, r.success, 'Valid payload should publish');
        System.assertEquals(202, RestContext.response.statusCode, 'Should accept with 202');
    }

    @isTest
    static void publishTurn_missingIntakeId_returns400() {
        buildRequest(JSON.serialize(new Map<String, Object>{ 'turnType' => 'client' }));

        Test.startTest();
        IntakeCoPilotIngest.IngestResult r = IntakeCoPilotIngest.publishTurn();
        Test.stopTest();

        System.assertEquals(false, r.success, 'Missing intakeId should fail');
        System.assertEquals(400, RestContext.response.statusCode, 'Should reject with 400');
    }

    @isTest
    static void publishTurn_malformedJson_returns400() {
        buildRequest('{ not json ');

        Test.startTest();
        IntakeCoPilotIngest.IngestResult r = IntakeCoPilotIngest.publishTurn();
        Test.stopTest();

        System.assertEquals(false, r.success, 'Malformed JSON should fail');
        System.assertEquals(400, RestContext.response.statusCode, 'Should reject with 400');
    }
}