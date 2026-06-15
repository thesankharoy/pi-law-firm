@RestResource(urlMapping='/intake/v1/*')
global with sharing class IntakeSubmissionService {
    global class IntakeResponse {
        public Boolean success;
        public String referenceNumber; // the submission UUID (tracking token)
        public String message;
        public List<String> errors;
        public transient Integer statusCode; // internal; not serialized to the body
    }

    @HttpPost
    global static IntakeResponse submitIntake() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        IntakeWrapper body;
        try {
            body = (IntakeWrapper) JSON.deserialize(req.requestBody.toString(), IntakeWrapper.class);
        } catch (Exception e) {
            res.statusCode = 400;
            IntakeResponse bad = new IntakeResponse();
            bad.success = false;
            bad.message = 'Malformed request body.';
            return bad;
        }

        IntakeResponse out = validateAndEnqueue(body);
        res.statusCode = out.statusCode;
        return out;
    }

    /** Shared by the REST endpoint and the LWC controller: validate -> enqueue. No DML, no staging. */
    public static IntakeResponse validateAndEnqueue(IntakeWrapper body) {
        IntakeResponse out = new IntakeResponse();
        out.errors = new List<String>();

        List<String> errors = validate(body);
        if (!errors.isEmpty()) {
            out.success = false;
            out.statusCode = 400;
            out.message = 'Validation failed.';
            out.errors = errors;
            return out;
        }

        if (String.isBlank(body.submissionUuid))
            body.submissionUuid = generateUuid();

        // Payload goes straight to async processing.
        System.enqueueJob(new IntakeSubmissionProcessor(new List<IntakeWrapper>{ body }));

        out.success = true;
        out.statusCode = 202;
        out.referenceNumber = body.submissionUuid;
        out.message = 'Submission received and is being processed.';
        return out;
    }

    // ---- helpers ----
    @TestVisible
    static List<String> validate(IntakeWrapper b) {
        List<String> errs = new List<String>();
        if (b == null) {
            errs.add('Empty body.');
            return errs;
        }
        if (String.isBlank(b.lastName))
            errs.add('lastName is required.');
        Boolean hasContact = String.isNotBlank(b.email) || String.isNotBlank(b.phone);
        if (!hasContact)
            errs.add('At least one of email or phone is required.');
        if (String.isNotBlank(b.email) && !Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', b.email)) {
            errs.add('email is invalid.');
        }
        if (b.consent != true)
            errs.add('consent is required.');
        return errs;
    }
    static String generateUuid() {
        String h = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
        return h.substring(0, 8) +
            '-' +
            h.substring(8, 12) +
            '-' +
            h.substring(12, 16) +
            '-' +
            h.substring(16, 20) +
            '-' +
            h.substring(20, 32);
    }
}