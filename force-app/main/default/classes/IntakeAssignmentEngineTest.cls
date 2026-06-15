@isTest
private class IntakeAssignmentEngineTest {
    @TestSetup
    static void setup() {
        // Create a queue
        Group q = new Group(Name = 'PI Test Queue', Type = 'Queue');
        insert q;
        QueueSObject qs = new QueueSObject(QueueId = q.Id, SObjectType = 'Intake__c');
        insert qs;

        // Create test user (use standard profile)
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User rep = new User(
            FirstName = 'Test',
            LastName = 'Rep',
            Email = 'rep@test.com',
            Username = 'rep@test' + System.now().getTime() + '.com',
            Alias = 'rep',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en',
            ProfileId = p.Id
        );
        insert rep;

        // Add rep to queue
        GroupMember gm = new GroupMember(GroupId = q.Id, UserOrGroupId = rep.Id);
        insert gm;

        // Create specialist record
        Intake_Specialist__c spec = new Intake_Specialist__c(
            User__c = rep.Id,
            Status__c = 'Active',
            Max_Capacity__c = 15
        );
        insert spec;

        // Create test party
        Contact party = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            RecordTypeId = recordTypeId('Contact', 'Individual'),
            Phone = '5551234567'
        );
        insert party;
    }

    @isTest
    static void testRoundRobinAssignment() {
        Contact party = [SELECT Id FROM Contact LIMIT 1];
        Intake_Specialist__c spec = [SELECT Id, User__c FROM Intake_Specialist__c LIMIT 1];

        Intake__c intake = new Intake__c(
            Client__c = party.Id,
            Incident_Type__c = 'Car Accident',
            Status__c = 'New',
            Sign_Up_Method__c = 'Phone'
        );
        insert intake;

        // Manually call the engine since CMT rules need separate deploy
        Group q = [SELECT Id FROM Group WHERE Type = 'Queue' LIMIT 1];
        intake.OwnerId = q.Id;
        update intake;

        Test.startTest();
        IntakeAssignmentEngine.assignIntakes(new List<Id>{ intake.Id });
        Test.stopTest();

        Intake__c result = [SELECT OwnerId FROM Intake__c WHERE Id = :intake.Id];
        System.assertNotEquals(null, result.OwnerId, 'Should be assigned to specialist');
        System.assertEquals(spec.User__c, result.OwnerId);
    }

    @isTest
    static void testNoActiveSpecialist_StaysInQueue() {
        Contact party = [SELECT Id FROM Contact LIMIT 1];
        Intake_Specialist__c spec = [SELECT Id FROM Intake_Specialist__c LIMIT 1];
        spec.Status__c = 'Inactive';
        update spec;

        Intake__c intake = new Intake__c(
            Client__c = party.Id,
            Incident_Type__c = 'Car Accident',
            Status__c = 'New',
            Sign_Up_Method__c = 'Web Form'
        );
        insert intake;

        Group q = [SELECT Id FROM Group WHERE Type = 'Queue' LIMIT 1];
        intake.OwnerId = q.Id;
        update intake;

        Test.startTest();
        IntakeAssignmentEngine.assignIntakes(new List<Id>{ intake.Id });
        Test.stopTest();

        Intake__c result = [SELECT OwnerId FROM Intake__c WHERE Id = :intake.Id];
        System.assertEquals(null, result.OwnerId, 'Should remain unassigned');
        System.assertEquals(q.Id, result.OwnerId, 'OwnerId should stay as queue');
    }

    @isTest
    static void testDrainQueueOnGoActive() {
        Contact party = [SELECT Id FROM Contact LIMIT 1];
        Intake_Specialist__c spec = [SELECT Id, User__c FROM Intake_Specialist__c LIMIT 1];
        spec.Status__c = 'Inactive';
        update spec;

        Group q = [SELECT Id FROM Group WHERE Type = 'Queue' LIMIT 1];

        // Create 3 intakes sitting in queue
        List<Intake__c> intakes = new List<Intake__c>();
        for (Integer i = 0; i < 3; i++) {
            intakes.add(
                new Intake__c(
                    Client__c = party.Id,
                    Incident_Type__c = 'Car Accident',
                    Status__c = 'New',
                    OwnerId = q.Id,
                    Sign_Up_Method__c = 'Web Form'
                )
            );
        }
        insert intakes;

        Test.startTest();
        IntakeAssignmentEngine.drainQueueForSpecialist(spec.User__c);
        Test.stopTest();

        // Note: drain won't assign because specialist is Inactive
        // Go active first then drain
        spec.Status__c = 'Active';
        update spec;

        IntakeAssignmentEngine.drainQueueForSpecialist(spec.User__c);

        List<Intake__c> assigned = [
            SELECT OwnerId
            FROM Intake__c
            WHERE OwnerId = :q.Id AND OwnerId = :spec.User__c
        ];
        System.assert(assigned.size() > 0, 'Intakes should be assigned after drain');
    }

    static Map<String, Id> rtCache = new Map<String, Id>();
    @TestVisible
    static Id recordTypeId(String objApi, String devName) {
        String key = objApi + '.' + devName;
        if (rtCache.containsKey(key))
            return rtCache.get(key);
        Id rid = Schema.getGlobalDescribe()
            .get(objApi)
            .getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get(devName)
            .getRecordTypeId();
        rtCache.put(key, rid);
        return rid;
    }
}