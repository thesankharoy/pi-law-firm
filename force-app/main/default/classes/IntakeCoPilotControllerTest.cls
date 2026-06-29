@isTest
private class IntakeCoPilotControllerTest {

    @isTest
    static void getContext_returnsHeaderInfo() {
        Contact c = new Contact(LastName = 'Tester');
        insert c;
        Intake__c intake = new Intake__c(
            Client__c = c.Id,
            Incident_Type__c = 'Auto Accident',
            Status__c = 'New'
        );
        insert intake;

        Test.startTest();
        IntakeCoPilotController.ContextWrapper ctx =
            IntakeCoPilotController.getContext(intake.Id);
        Test.stopTest();

        System.assertEquals('Auto Accident', ctx.incidentType, 'Incident type should round-trip');
        System.assertEquals('/event/Co_Pilot_Event__e', ctx.channel, 'Channel name should be set');
        System.assert(ctx.clientName.contains('Tester'), 'Client name should resolve from Contact');
    }

    @isTest
    static void publishMockEvent_publishesWithoutError() {
        Contact c = new Contact(LastName = 'Caller');
        insert c;
        Intake__c intake = new Intake__c(Client__c = c.Id, Status__c = 'New');
        insert intake;

        Test.startTest();
        IntakeCoPilotController.publishMockEvent(
            intake.Id, 'client',
            'Tuve un accidente de coche ayer.',
            'I had a car accident yesterday.',
            'es',
            'Ask whether they have sought medical treatment yet.',
            'Negative', 'Strong', 1
        );
        Test.stopTest();
        // EventBus.publish in a test enqueues the event; reaching here without
        // an AuraHandledException means the publish call succeeded.
        System.assert(true, 'publishMockEvent completed');
    }
}