@RestResource(urlMapping='/intake/v1/*')
global with sharing class IntakeSubmissionService {
    global class IntakeResponse {
        public Boolean success;
        public String intakeReference; // Intake__c.Name, for human reference
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

        IntakeResponse out = validateAndProcess(body);
        res.statusCode = out.statusCode;
        return out;
    }

    /**
     * Shared by the REST endpoint and the LWC controller.
     * Synchronous — no Queueable. Caller knows immediately whether creation
     * succeeded and gets the real Intake Name back.
     */
    public static IntakeResponse validateAndProcess(IntakeWrapper body) {
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

        try {
            PartyIntakeService.ProcessResult result = PartyIntakeService.process(body);
            out.success = true;
            out.statusCode = 201;
            out.intakeReference = result.intakeReference;
            out.message = result.status == 'Needs Review'
                ? 'Submission received. Our team will review and contact you shortly.'
                : 'Submission received successfully.';
        } catch (Exception e) {
            out.success = false;
            out.statusCode = 500;
            out.message = 'We could not process your submission. Please try again or call our office.';
            System.debug(
                LoggingLevel.ERROR,
                'Intake creation failed: ' + e.getMessage() + ' | ' + e.getStackTraceString()
            );
        }

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
}