/**
 * IntakeAgentService
 * -----------------------------------------------------------------------------
 * Thin invocable entry point for the Agentforce "Sarah" PI intake agent.
 *
 * Design (Thin Entry Point pattern):
 *   - This class is the gateway the Atlas reasoning engine calls.
 *   - Dedup + Contact/Intake__c/Role__c creation is delegated to the platform's
 *     canonical service PartyIntakeService.process(IntakeWrapper).
 *   - This class adds three things on top:
 *       1. A defensive USA-only guard (the agent already gates conversationally).
 *       2. Server-side fuzzy picklist coercion, so a free-text client phrase is
 *          mapped to a real ACTIVE picklist value before we ever write it.
 *       3. The Incident_Age__c follow-up field (not present on IntakeWrapper).
 *
 * `without sharing` mirrors PartyIntakeService so dedup queries see all Contacts
 * regardless of the running user's sharing (the agent runs as a service user).
 */
public without sharing class IntakeAgentService {
    // Tokens we accept as "United States" on the defensive guard.
    private static final Set<String> US_TOKENS = new Set<String>{
        'us',
        'usa',
        'u.s.',
        'u.s.a.',
        'united states',
        'united states of america',
        'america',
        'the us',
        'the usa'
    };

    // ---------------------------------------------------------------------
    //  Invocable entry point
    // ---------------------------------------------------------------------
    @InvocableMethod(
        label='Create PI Intake'
        description='Creates the injured client as a Contact, an Intake case record, and a Client Role junction record after qualification. Call this exactly once, only after the client has confirmed they are located in the United States and you have gathered at minimum: the incident type, first name, last name, and either an email address or a phone number. Pass the closest matching picklist option for each qualifying field.'
    )
    public static List<Response> createIntake(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            out.add(processOne(r));
        }
        return out;
    }

    // ---------------------------------------------------------------------
    //  Core
    // ---------------------------------------------------------------------
    private static Response processOne(Request r) {
        Response res = new Response();

        // 1) Defensive USA guard ------------------------------------------
        if (!isUsa(r.country)) {
            res.success = false;
            res.message = 'Client is located outside the United States. No record was created.';
            return res;
        }

        // 2) Mandatory-field validation -----------------------------------
        List<String> missing = new List<String>();
        if (String.isBlank(r.incidentType))
            missing.add('incident type');
        if (String.isBlank(r.firstName))
            missing.add('first name');
        if (String.isBlank(r.lastName))
            missing.add('last name');
        if (String.isBlank(r.email) && String.isBlank(r.phone)) {
            missing.add('an email address or phone number');
        }
        if (!missing.isEmpty()) {
            res.success = false;
            res.message = 'Cannot create the intake yet — still need: ' + String.join(missing, ', ') + '.';
            return res;
        }

        // 3) Build the platform wrapper (picklists coerced server-side) ----
        IntakeWrapper w = new IntakeWrapper();
        w.firstName = trimToNull(r.firstName);
        w.lastName = trimToNull(r.lastName);
        w.email = trimToNull(r.email);
        w.phone = trimToNull(r.phone);
        w.country = 'United States';
        w.dateOfBirth = trimToNull(r.dateOfBirth); // yyyy-MM-dd string
        w.incidentType = coerce('Incident_Type__c', r.incidentType);
        w.incidentDate = trimToNull(r.incidentDate); // yyyy-MM-dd string
        w.description = trimToNull(r.incidentDescription);
        w.injurySeverity = coerce('Injury_Severity__c', r.injurySeverity);
        w.medicalTreatmentStatus = coerce('Medical_Treatment_Status__c', r.medicalTreatmentStatus);
        w.insuranceAvailable = coerce('Insurance_Available__c', r.insuranceAvailable);
        w.liabilityClarity = coerce('Liability_Clarity__c', r.liabilityClarity);
        w.policeCalled = (r.policeCalled == true);
        w.source = 'Chatbot';
        w.consent = true;

        // 4) Delegate to the canonical web-to-intake service --------------
        PartyIntakeService.ProcessResult pr;
        try {
            pr = PartyIntakeService.process(w);
        } catch (Exception e) {
            res.success = false;
            res.message = 'We hit a problem while saving your details. A team member will reach out to you shortly.';
            res.errorDetail = e.getMessage();
            return res;
        }

        // 5) Incident_Age__c follow-up field (not on IntakeWrapper) -------
        String ageVal = coerce('Incident_Age__c', r.incidentAge);
        if (String.isNotBlank(ageVal) && pr.intakeId != null) {
            try {
                update new Intake__c(Id = pr.intakeId, Incident_Age__c = ageVal);
            } catch (Exception ignore) {
                // Non-fatal: the intake already exists; age is supplementary.
            }
        }

        // 6) Shape the response for the agent -----------------------------
        res.success = true;
        res.intakeId = pr.intakeId;
        res.intakeReference = pr.intakeReference;
        res.contactId = pr.partyId;
        res.needsReview = (pr.matchCount != null && pr.matchCount >= 2);
        res.message = res.needsReview
            ? 'Intake ' + pr.intakeReference + ' was created and flagged for a quick identity review.'
            : 'Intake ' + pr.intakeReference + ' was created successfully.';
        return res;
    }

    // ---------------------------------------------------------------------
    //  Helpers
    // ---------------------------------------------------------------------
    private static Boolean isUsa(String country) {
        if (String.isBlank(country))
            return false;
        return US_TOKENS.contains(country.trim().toLowerCase());
    }

    private static String trimToNull(String s) {
        return String.isBlank(s) ? null : s.trim();
    }

    /**
     * Fuzzy-coerce a raw client phrase to the closest ACTIVE picklist value on
     * Intake__c. Returns null when nothing reasonable matches so we never write
     * an invalid value. Match order: exact (normalised) -> synonym map ->
     * substring (either direction) -> token overlap (best score).
     */
    @TestVisible
    private static String coerce(String fieldApi, String raw) {
        if (String.isBlank(raw))
            return null;
        List<String> values = activePicklist(fieldApi);
        if (values.isEmpty())
            return null;

        String norm = normalize(raw);

        // exact
        for (String v : values) {
            if (normalize(v) == norm)
                return v;
        }
        // synonym
        String syn = synonym(fieldApi, norm);
        if (syn != null) {
            for (String v : values) {
                if (normalize(v) == normalize(syn))
                    return v;
            }
        }
        // substring either direction
        for (String v : values) {
            String nv = normalize(v);
            if (String.isNotBlank(nv) && (nv.contains(norm) || norm.contains(nv)))
                return v;
        }
        // token overlap
        Set<String> rawTokens = tokens(norm);
        String best;
        Integer bestScore = 0;
        for (String v : values) {
            Integer score = 0;
            for (String t : tokens(normalize(v))) {
                if (rawTokens.contains(t))
                    score++;
            }
            if (score > bestScore) {
                bestScore = score;
                best = v;
            }
        }
        return bestScore > 0 ? best : null;
    }

    private static Map<String, List<String>> PICKLIST_CACHE = new Map<String, List<String>>();
    private static List<String> activePicklist(String fieldApi) {
        if (PICKLIST_CACHE.containsKey(fieldApi))
            return PICKLIST_CACHE.get(fieldApi);
        List<String> vals = new List<String>();
        try {
            Schema.SObjectField f = Schema.getGlobalDescribe()
                .get('Intake__c')
                .getDescribe()
                .fields.getMap()
                .get(fieldApi);
            if (f != null) {
                for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues()) {
                    if (e.isActive())
                        vals.add(e.getValue());
                }
            }
        } catch (Exception ignore) {
            // Field not present yet (e.g. Incident_Age__c not deployed) -> empty.
        }
        PICKLIST_CACHE.put(fieldApi, vals);
        return vals;
    }

    private static String normalize(String s) {
        if (s == null)
            return '';
        return s.toLowerCase()
            .replaceAll('[^a-z0-9 ]', ' ') // collapse dashes/punctuation incl. en-dash
            .replaceAll(' +', ' ')
            .trim();
    }

    private static Set<String> tokens(String s) {
        Set<String> t = new Set<String>();
        for (String w : s.split(' ')) {
            if (w.length() > 2)
                t.add(w);
        }
        return t;
    }

    private static String synonym(String fieldApi, String norm) {
        Map<String, String> m = SYNONYMS.get(fieldApi);
        if (m == null)
            return null;
        for (String key : m.keySet()) {
            if (norm.contains(key))
                return m.get(key);
        }
        return null;
    }

    /**
     * Domain synonyms for phrases a client uses that do NOT share a word with
     * the picklist label (so substring/token matching alone would miss them).
     */
    private static final Map<String, Map<String, String>> SYNONYMS = new Map<String, Map<String, String>>{
        'Incident_Type__c' => new Map<String, String>{
            'car' => 'Auto Accident',
            'vehicle' => 'Auto Accident',
            'crash' => 'Auto Accident',
            'collision' => 'Auto Accident',
            'rear end' => 'Auto Accident',
            'rear ended' => 'Auto Accident',
            'truck' => 'Auto Accident',
            'motorcycle' => 'Auto Accident',
            'driver' => 'Auto Accident',
            'fell' => 'Slip and Fall',
            'fall' => 'Slip and Fall',
            'tripped' => 'Slip and Fall',
            'wet floor' => 'Slip and Fall',
            'doctor' => 'Medical Malpractice',
            'hospital' => 'Medical Malpractice',
            'surgery' => 'Medical Malpractice',
            'misdiagnos' => 'Medical Malpractice',
            'work' => 'Workers Compensation',
            'job' => 'Workers Compensation',
            'on the clock' => 'Workers Compensation',
            'dog' => 'Dog Bite',
            'bitten' => 'Dog Bite',
            'bit me' => 'Dog Bite',
            'died' => 'Wrongful Death',
            'passed away' => 'Wrongful Death',
            'defective' => 'Product Liability',
            'product' => 'Product Liability',
            'malfunction' => 'Product Liability'
        },
        'Injury_Severity__c' => new Map<String, String>{
            'died' => 'Fatality',
            'death' => 'Fatality',
            'passed away' => 'Fatality',
            'killed' => 'Fatality',
            'life threatening' => 'Critical',
            'icu' => 'Critical',
            'intensive care' => 'Critical',
            'broke' => 'Severe',
            'broken' => 'Severe',
            'fracture' => 'Severe',
            'surgery' => 'Severe',
            'hospitalized' => 'Severe',
            'whiplash' => 'Moderate',
            'sprain' => 'Moderate',
            'concussion' => 'Moderate',
            'bruise' => 'Minor',
            'scrape' => 'Minor',
            'sore' => 'Minor',
            'cut' => 'Minor'
        },
        'Medical_Treatment_Status__c' => new Map<String, String>{
            'haven t' => 'Not Started',
            'have not' => 'Not Started',
            'not yet' => 'Not Started',
            'no treatment' => 'Not Started',
            'seeing' => 'Active',
            'currently' => 'Active',
            'ongoing' => 'Active',
            'therapy' => 'Active',
            'physio' => 'Active',
            'paused' => 'On Hold',
            'stopped' => 'On Hold',
            'waiting' => 'On Hold',
            'released' => 'Discharged',
            'discharged' => 'Discharged',
            'all done' => 'Discharged'
        },
        'Insurance_Available__c' => new Map<String, String>{
            'business' => 'Commercial',
            'company' => 'Commercial',
            'employer' => 'Commercial',
            'my own' => 'Personal',
            'mine' => 'Personal',
            'personal' => 'Personal',
            'don t know' => 'Unknown',
            'not sure' => 'Unknown',
            'no idea' => 'Unknown',
            'no insurance' => 'None',
            'uninsured' => 'None',
            'none' => 'None'
        },
        'Liability_Clarity__c' => new Map<String, String>{
            'their fault' => 'Other_Party_Fault',
            'other driver' => 'Other_Party_Fault',
            'not my fault' => 'Other_Party_Fault',
            'they caused' => 'Other_Party_Fault',
            'both' => 'Shared_Fault',
            'partly' => 'Shared_Fault',
            'my fault too' => 'Shared_Fault',
            'we both' => 'Shared_Fault',
            'not sure' => 'Unclear',
            'don t know' => 'Unclear',
            'unclear' => 'Unclear'
        }
    };

    // ---------------------------------------------------------------------
    //  Invocable DTOs
    // ---------------------------------------------------------------------
    public class Request {
        @InvocableVariable(required=true label='First Name' description='The client first name.')
        public String firstName;

        @InvocableVariable(required=true label='Last Name' description='The client last name.')
        public String lastName;

        @InvocableVariable(
            label='Email'
            description='The client email address. Either email or phone must be provided.'
        )
        public String email;

        @InvocableVariable(label='Phone' description='The client phone number. Either email or phone must be provided.')
        public String phone;

        @InvocableVariable(
            label='Country'
            description='The country where the client is currently located. Only United States clients are accepted.'
        )
        public String country;

        @InvocableVariable(label='Date of Birth' description='The client date of birth in yyyy-MM-dd format. Optional.')
        public String dateOfBirth;

        @InvocableVariable(
            required=true
            label='Incident Type'
            description='What happened. Map the client story to the closest of: Auto Accident, Slip and Fall, Medical Malpractice, Workers Compensation, Product Liability, Dog Bite, Wrongful Death, Other.'
        )
        public String incidentType;

        @InvocableVariable(
            label='Incident Date'
            description='The date the incident occurred in yyyy-MM-dd format. Optional if unknown.'
        )
        public String incidentDate;

        @InvocableVariable(
            label='Incident Age'
            description='How long ago the incident happened, used only when the exact date is unknown. One of: Within 7 Days, 8-30 Days, 31-90 Days, 90+ Days.'
        )
        public String incidentAge;

        @InvocableVariable(
            label='Incident Description'
            description='A brief narrative of what happened, in the client own words.'
        )
        public String incidentDescription;

        @InvocableVariable(
            label='Injury Severity'
            description='How serious the injuries are. Map to the closest of: Minor, Moderate, Severe, Critical, Fatality.'
        )
        public String injurySeverity;

        @InvocableVariable(
            label='Medical Treatment Status'
            description='Where the client is with medical care. Map to the closest of: Not Started, Active, On Hold, Discharged.'
        )
        public String medicalTreatmentStatus;

        @InvocableVariable(
            label='Insurance Available'
            description='Whether insurance applies. Map to the closest of: Commercial, Personal, Unknown, None.'
        )
        public String insuranceAvailable;

        @InvocableVariable(
            label='Liability Clarity'
            description='Who appears to be at fault. Map to the closest of: Other_Party_Fault, Shared_Fault, Unclear.'
        )
        public String liabilityClarity;

        @InvocableVariable(
            label='Police Called'
            description='True if police were called to the scene, otherwise false.'
        )
        public Boolean policeCalled;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True when the intake was created.')
        public Boolean success = false;

        @InvocableVariable(label='Message' description='A short, human-readable result you can relay to the client.')
        public String message;

        @InvocableVariable(
            label='Intake Number'
            description='The created intake reference number, for example INT-00042.'
        )
        public String intakeReference;

        @InvocableVariable(label='Intake Id' description='Record Id of the created intake.')
        public Id intakeId;

        @InvocableVariable(label='Contact Id' description='Record Id of the client Contact.')
        public Id contactId;

        @InvocableVariable(
            label='Needs Review'
            description='True when the identity matched multiple existing contacts and a human should confirm.'
        )
        public Boolean needsReview = false;

        @InvocableVariable(
            label='Error Detail'
            description='Internal error detail. Do not read this out to the client.'
        )
        public String errorDetail;
    }
}