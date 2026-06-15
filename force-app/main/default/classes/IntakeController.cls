public with sharing class IntakeController {
    /**
     * Called by the Experience Cloud LWC. Runs in the site user's own context
     * (logged-in member or guest) — no OAuth, no client id/secret.
     * payloadJson matches the IntakeWrapper shape.
     */
    @AuraEnabled
    public static String createIntake(String payloadJson) {
        IntakeWrapper body;
        try {
            body = (IntakeWrapper) JSON.deserialize(payloadJson, IntakeWrapper.class);
        } catch (Exception e) {
            throw new AuraHandledException('Malformed submission.');
        }
        IntakeSubmissionService.IntakeResponse res = IntakeSubmissionService.validateAndEnqueue(body);
        if (res.success != true) {
            throw new AuraHandledException(
                (res.errors != null && !res.errors.isEmpty()) ? String.join(res.errors, ' ') : res.message
            );
        }
        return res.referenceNumber;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, List<PicklistOption>> getIntakePicklists() {
        Set<String> fields = new Set<String>{
            'Incident_Type__c',
            'Injury_Severity__c',
            'Medical_Treatment_Status__c',
            'Insurance_Available__c',
            'Liability_Clarity__c'
        };
        Map<String, Schema.SObjectField> fieldMap = Intake__c.SObjectType.getDescribe().fields.getMap();
        Map<String, List<PicklistOption>> result = new Map<String, List<PicklistOption>>();
        for (String f : fields) {
            List<PicklistOption> opts = new List<PicklistOption>();
            for (Schema.PicklistEntry e : fieldMap.get(f.toLowerCase()).getDescribe().getPicklistValues()) {
                if (e.isActive())
                    opts.add(new PicklistOption(e.getLabel(), e.getValue()));
            }
            result.put(f, opts);
        }
        return result;
    }

    public class PicklistOption {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}