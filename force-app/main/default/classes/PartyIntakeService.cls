public without sharing class PartyIntakeService {
    public class ProcessResult {
        public Id partyId;
        public Id intakeId;
        public String intakeReference; // Intake__c.Name, for human reference
        public Integer matchCount = 0;
        public String status; // 'Processed' | 'Needs Review'
        public Boolean createdNewParty = false;
    }

    public static ProcessResult process(IntakeWrapper inwrapper) {
        ProcessResult r = new ProcessResult();

        String email = normalizeEmail(inwrapper.email);
        String phone = digits(inwrapper.phone);
        String lastName = (inwrapper.lastName != null) ? inwrapper.lastName.trim() : null;
        Date dob = parseDate(inwrapper.dateOfBirth);

        Set<Id> candidateIds = findCandidateParties(email, phone, lastName, dob);
        r.matchCount = candidateIds.size();

        Contact party;
        if (candidateIds.size() == 1) {
            party = new Contact(Id = new List<Id>(candidateIds)[0]);
        } else if (candidateIds.isEmpty()) {
            party = buildParty(inwrapper, email, phone);
            insert party;
            r.createdNewParty = true;
        }
        Boolean ambiguous = candidateIds.size() > 1;

        Intake__c intake = new Intake__c(
            RecordTypeId = recordTypeId('Intake__c', 'New_Intake'),
            Client__c = (party != null ? party.Id : null),
            Incident_Type__c = matchPicklist('Intake__c', 'Incident_Type__c', inwrapper.incidentType),
            Incident_Date__c = parseDate(inwrapper.incidentDate),
            Status__c = ambiguous ? 'Under Review' : 'New',
            Incident_Location__CountryCode__s = matchPicklist(
                'Intake__c',
                'Incident_Location__CountryCode__s',
                inwrapper.country
            ),
            Incident_Description__c = trimTo(inwrapper.description, 32000),
            Injury_Severity__c = matchPicklist('Intake__c', 'Injury_Severity__c', inwrapper.injurySeverity),
            Medical_Treatment_Status__c = matchPicklist(
                'Intake__c',
                'Medical_Treatment_Status__c',
                inwrapper.medicalTreatmentStatus
            ),
            Police_Called__c = (inwrapper.policeCalled == true),
            Insurance_Available__c = matchPicklist('Intake__c', 'Insurance_Available__c', inwrapper.insuranceAvailable),
            Liability_Clarity__c = matchPicklist('Intake__c', 'Liability_Clarity__c', inwrapper.liabilityClarity),
            Intake_Phone__c = phone,
            Source__c = 'Web',
            Sign_Up_Method__c = 'Web'
        );
        insert intake;
        r.intakeId = intake.Id;

        // Auto-number Name is set by the server on insert — must re-query to get it
        r.intakeReference = [SELECT Name FROM Intake__c WHERE Id = :intake.Id LIMIT 1].Name;

        if (party != null) {
            insert new Role__c(
                Role__c = 'Client',
                Party__c = party.Id,
                Intake__c = intake.Id,
                Comments__c = 'Auto-created from web intake — ' + r.intakeReference
            );
            r.partyId = party.Id;
            r.status = 'Processed';
        } else {
            r.status = 'Needs Review';
        }
        return r;
    }

    @TestVisible
    static Set<Id> findCandidateParties(String email, String phone, String lastName, Date dob) {
        Set<Id> ids = new Set<Id>();

        if (String.isNotBlank(email)) {
            for (Contact p : [SELECT Id FROM Contact WHERE Email = :email LIMIT 50])
                ids.add(p.Id);
        }

        if (String.isNotBlank(phone)) {
            for (Contact p : [SELECT Id FROM Contact WHERE Phone = :phone LIMIT 50])
                ids.add(p.Id);
        }

        if (String.isNotBlank(lastName) && dob != null) {
            for (Contact p : [
                SELECT Id
                FROM Contact
                WHERE LasTName = :lastName AND Birthdate = :dob
                LIMIT 50
            ])
                ids.add(p.Id);
        }
        return ids;
    }

    static Contact buildParty(IntakeWrapper req, String email, String phone) {
        String first = (req.firstName != null) ? req.firstName.trim() : '';
        String last = (req.lastName != null) ? req.lastName.trim() : 'Unknown Party';

        return new Contact(
            RecordTypeId = recordTypeId('Contact', 'Individual'),
            FirstName = trimTo(req.firstName, 80),
            LastName = trimTo(req.lastName, 80),
            Email = email,
            Phone = phone,
            Birthdate = parseDate(req.dateOfBirth)
        );
    }

    // ---- normalization / helpers ----
    @TestVisible
    static String normalizeEmail(String e) {
        return String.isBlank(e) ? null : e.trim().toLowerCase();
    }
    @TestVisible
    static String digits(String p) {
        if (String.isBlank(p))
            return null;
        String d = p.replaceAll('[^0-9]', '');
        if (d.length() > 10)
            d = d.substring(d.length() - 10); // US: keep last 10
        return String.isBlank(d) ? null : d;
    }
    static String trimTo(String v, Integer len) {
        if (v == null)
            return null;
        v = v.trim();
        return v.length() > len ? v.substring(0, len) : v;
    }
    static Date parseDate(String s) {
        if (String.isBlank(s))
            return null;
        try {
            return Date.valueOf(s.trim());
        } catch (Exception e) {
            return null;
        }
    }
    static String mapSource(String objApi, String fieldApi, String raw) {
        String m = matchPicklist(objApi, fieldApi, raw);
        return (m != null) ? m : 'Web';
    }
    @TestVisible
    static String matchPicklist(String objApi, String fieldApi, String raw) {
        if (String.isBlank(raw))
            return null;
        Schema.DescribeFieldResult dfr = Schema.getGlobalDescribe()
            .get(objApi)
            .getDescribe()
            .fields.getMap()
            .get(fieldApi)
            .getDescribe();
        for (Schema.PicklistEntry e : dfr.getPicklistValues()) {
            if (e.getValue().equalsIgnoreCase(raw) || e.getLabel().equalsIgnoreCase(raw))
                return e.getValue();
        }
        return null;
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