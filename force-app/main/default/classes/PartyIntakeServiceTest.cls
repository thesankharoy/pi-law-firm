/**
 * PartyIntakeServiceTest
 * Covers the find-or-create service, the Queueable processor, and the REST
 * endpoint across the four key scenarios: new identity, returning client
 * (matched by email / phone / name+DOB), and ambiguous (multi-match) routing.
 */
@IsTest
private class PartyIntakeServiceTest {

    // ---- helpers ----
    static Intake_Submission__c stageSubmission(String uuid, String first, String last,
            String email, String phone, String mobile, Date dob, String incidentType) {
        Intake_Submission__c s = new Intake_Submission__c(
            Submission_UUID__c = uuid,
            Status__c          = 'Received',
            First_Name__c      = first,
            Last_Name__c       = last,
            Email__c           = email,
            Phone__c           = phone,
            Mobile_Phone__c    = mobile,
            Date_of_Birth__c   = dob,
            Incident_Type__c   = incidentType,
            Incident_Date__c   = Date.today().addDays(-10),
            Incident_Location__c = 'Main St & 1st Ave',
            Description__c     = 'Rear-ended at a red light.',
            Source__c          = 'Google',
            Consent__c         = true
        );
        insert s;
        return s;
    }

    static Id individualRt() {
        return Schema.SObjectType.Party__c.getRecordTypeInfosByDeveloperName()
                .get('Litify_Individual').getRecordTypeId();
    }

    // 0 matches -> create Party + Intake + Role
    @IsTest
    static void testNewIdentityCreatesAll() {
        IntakeSubmissionProcessor.disableAsync = true; // unit-test the service directly
        Intake_Submission__c s = stageSubmission('uuid-new-1', 'Jane', 'Doe',
            'jane.doe@example.com', '(415) 555-1212', null, Date.newInstance(1990,5,1), 'Auto Accident');

        Test.startTest();
        PartyIntakeService.ProcessResult r = PartyIntakeService.process(s);
        Test.stopTest();

        System.assertEquals(0, r.matchCount, 'No existing party expected');
        System.assert(r.createdNewParty, 'Should have created a new Party');
        System.assertEquals('Processed', r.status);
        System.assertNotEquals(null, r.partyId);
        System.assertNotEquals(null, r.intakeId);

        Intake__c intake = [SELECT Id, Client__c, Case_Type__c, Sign_Up_Method__c, Case_Status__c,
                                   Source__c, Origin_Submission__c FROM Intake__c WHERE Id = :r.intakeId];
        System.assertEquals(r.partyId, intake.Client__c);
        System.assertEquals('Auto Accident', intake.Case_Type__c, 'Raw case type should map to picklist value');
        System.assertEquals('Web', intake.Sign_Up_Method__c);
        System.assertEquals('New', intake.Case_Status__c);
        System.assertEquals(s.Id, intake.Origin_Submission__c);

        List<Role__c> roles = [SELECT Id, Role__c, Party__c, Intake__c FROM Role__c WHERE Intake__c = :r.intakeId];
        System.assertEquals(1, roles.size());
        System.assertEquals('Client', roles[0].Role__c);
        System.assertEquals(r.partyId, roles[0].Party__c);
    }

    // 1 match by email -> reuse Party
    @IsTest
    static void testReturningByEmail() {
        IntakeSubmissionProcessor.disableAsync = true;
        Party__c existing = new Party__c(Name='John Smith', RecordTypeId=individualRt(),
            First_Name__c='John', Last_Name__c='Smith', Email__c='john.smith@example.com', Type__c='Person');
        insert existing;

        Intake_Submission__c s = stageSubmission('uuid-email-1', 'John', 'Smith',
            'JOHN.SMITH@example.com', null, null, null, 'Slip and Fall'); // different case email

        Test.startTest();
        PartyIntakeService.ProcessResult r = PartyIntakeService.process(s);
        Test.stopTest();

        System.assertEquals(1, r.matchCount);
        System.assert(!r.createdNewParty, 'Should reuse existing Party');
        System.assertEquals(existing.Id, r.partyId);
        System.assertEquals('Processed', r.status);
        System.assertEquals(1, [SELECT COUNT() FROM Party__c]); // no duplicate Party
    }

    // 1 match by phone digits (different formatting) -> reuse Party
    @IsTest
    static void testReturningByPhone() {
        IntakeSubmissionProcessor.disableAsync = true;
        Party__c existing = new Party__c(Name='Mary Jones', RecordTypeId=individualRt(),
            First_Name__c='Mary', Last_Name__c='Jones', Party_Phone__c='415-555-9999',
            Phone_Digits__c='4155559999', Type__c='Person');
        insert existing;

        Intake_Submission__c s = stageSubmission('uuid-phone-1', 'Mary', 'Jones',
            null, '+1 (415) 555.9999', null, null, 'Dog Bite'); // same number, different format

        Test.startTest();
        PartyIntakeService.ProcessResult r = PartyIntakeService.process(s);
        Test.stopTest();

        System.assertEquals(1, r.matchCount);
        System.assertEquals(existing.Id, r.partyId);
        System.assertEquals(1, [SELECT COUNT() FROM Party__c]);
    }

    // 1 match by last name + DOB -> reuse Party
    @IsTest
    static void testReturningByNameDob() {
        IntakeSubmissionProcessor.disableAsync = true;
        Date dob = Date.newInstance(1985, 3, 15);
        Party__c existing = new Party__c(Name='Sam Lee', RecordTypeId=individualRt(),
            First_Name__c='Sam', Last_Name__c='Lee', Date_of_Birth__c=dob, Type__c='Person');
        insert existing;

        Intake_Submission__c s = stageSubmission('uuid-dob-1', 'Samuel', 'Lee',
            'different@example.com', null, null, dob, 'Other');

        Test.startTest();
        PartyIntakeService.ProcessResult r = PartyIntakeService.process(s);
        Test.stopTest();

        System.assertEquals(1, r.matchCount);
        System.assertEquals(existing.Id, r.partyId);
    }

    // 2+ matches -> ambiguous: Intake created, no Party/Role, Needs Review
    @IsTest
    static void testAmbiguousRoutesToReview() {
        IntakeSubmissionProcessor.disableAsync = true;
        insert new List<Party__c>{
            new Party__c(Name='Dup One', RecordTypeId=individualRt(), Last_Name__c='Dup',
                         Email__c='dup@example.com', Type__c='Person'),
            new Party__c(Name='Dup Two', RecordTypeId=individualRt(), Last_Name__c='Dup',
                         Phone_Digits__c='2025551234', Type__c='Person')
        };

        // matches party 1 by email AND party 2 by phone -> 2 candidates
        Intake_Submission__c s = stageSubmission('uuid-amb-1', 'Dup', 'Dup',
            'dup@example.com', '202-555-1234', null, null, 'Auto Accident');

        Test.startTest();
        PartyIntakeService.ProcessResult r = PartyIntakeService.process(s);
        Test.stopTest();

        System.assertEquals(2, r.matchCount);
        System.assertEquals('Needs Review', r.status);
        System.assertEquals(null, r.partyId, 'No party resolved when ambiguous');
        System.assertNotEquals(null, r.intakeId, 'Intake still created');

        Intake__c intake = [SELECT Case_Status__c, Client__c FROM Intake__c WHERE Id = :r.intakeId];
        System.assertEquals('Needs Party Review', intake.Case_Status__c);
        System.assertEquals(null, intake.Client__c);
        System.assertEquals(0, [SELECT COUNT() FROM Role__c WHERE Intake__c = :r.intakeId]);
    }

    // Trigger -> Queueable end-to-end
    @IsTest
    static void testTriggerEnqueuesAndProcesses() {
        Test.startTest();
        Intake_Submission__c s = stageSubmission('uuid-trigger-1', 'Async', 'Tester',
            'async@example.com', null, null, null, 'Auto Accident');
        Test.stopTest(); // flushes the Queueable enqueued by the trigger

        Intake_Submission__c after = [SELECT Status__c, Created_Intake__c, Matched_Party__c, Match_Count__c
                                      FROM Intake_Submission__c WHERE Id = :s.Id];
        System.assertEquals('Processed', after.Status__c);
        System.assertNotEquals(null, after.Created_Intake__c);
        System.assertNotEquals(null, after.Matched_Party__c);
    }

    // REST endpoint: valid POST stages a submission and returns 202
    @IsTest
    static void testRestEndpointSuccess() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/intake/v1';
        req.httpMethod = 'POST';
        Map<String,Object> payload = new Map<String,Object>{
            'submissionUuid' => 'uuid-rest-1',
            'firstName' => 'Web', 'lastName' => 'Lead',
            'email' => 'web.lead@example.com',
            'incidentType' => 'Auto Accident',
            'incidentDate' => String.valueOf(Date.today().addDays(-5)),
            'consent' => true
        };
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        IntakeSubmissionService.IntakeResponse out = IntakeSubmissionService.submitIntake();
        Test.stopTest(); // flushes Queueable from the after-insert trigger

        System.assertEquals(true, out.success);
        System.assertEquals(202, RestContext.response.statusCode);
        System.assertNotEquals(null, out.referenceNumber);

        Intake_Submission__c sub = [SELECT Status__c, Created_Intake__c FROM Intake_Submission__c
                                    WHERE Submission_UUID__c = 'uuid-rest-1'];
        System.assertEquals('Processed', sub.Status__c);
        System.assertNotEquals(null, sub.Created_Intake__c);
    }

    // REST endpoint: idempotent re-POST returns the same submission, no duplicate
    @IsTest
    static void testRestIdempotency() {
        insert new Intake_Submission__c(Submission_UUID__c='dupe-uuid', Status__c='Processed',
            Last_Name__c='Existing', Email__c='e@example.com', Consent__c=true);

        RestRequest req = new RestRequest();
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String,Object>{
            'submissionUuid' => 'dupe-uuid', 'lastName' => 'Existing',
            'email' => 'e@example.com', 'consent' => true }));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        IntakeSubmissionService.IntakeResponse out = IntakeSubmissionService.submitIntake();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(1, [SELECT COUNT() FROM Intake_Submission__c WHERE Submission_UUID__c='dupe-uuid']);
    }

    // REST endpoint: validation failure returns 400
    @IsTest
    static void testRestValidationFails() {
        RestRequest req = new RestRequest();
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String,Object>{
            'firstName' => 'NoLastName', 'consent' => true })); // missing lastName + contact
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        IntakeSubmissionService.IntakeResponse out = IntakeSubmissionService.submitIntake();
        Test.stopTest();

        System.assertEquals(false, out.success);
        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(out.errors.size() >= 2, 'Expected lastName + contact errors');
    }

    // Shared-secret gate rejects a bad/missing header when a secret is configured
    @IsTest
    static void testSharedSecretRejected() {
        insert new Intake_Web_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(),
            Shared_Secret__c = 'topsecret');

        RestRequest req = new RestRequest();
        req.httpMethod = 'POST';
        req.headers.put('X-Intake-Secret', 'wrong');
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String,Object>{
            'lastName' => 'X', 'email' => 'x@example.com', 'consent' => true }));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        IntakeSubmissionService.IntakeResponse out = IntakeSubmissionService.submitIntake();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
        System.assertEquals(false, out.success);
    }

    // Normalization helpers
    @IsTest
    static void testNormalizationHelpers() {
        System.assertEquals('a@b.com', PartyIntakeService.normalizeEmail('  A@B.CoM '));
        System.assertEquals('4155551212', PartyIntakeService.digits('+1 (415) 555-1212'));
        System.assertEquals(null, PartyIntakeService.digits('   '));
    }
}
