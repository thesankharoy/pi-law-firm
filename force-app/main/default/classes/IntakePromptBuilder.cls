public with sharing class IntakePromptBuilder {

    public class InputWrapper {
        @InvocableVariable(label='Intake Record Id' required=true)
        public Id intakeId;
    }

    public class OutputWrapper {
        @InvocableVariable(label='Generated Prompt')
        @AuraEnabled
        public String prompt;

        @InvocableVariable(label='Missing Fields Count')
        @AuraEnabled
        public Integer missingCount;

        @InvocableVariable(label='All Fields Filled')
        @AuraEnabled
        public Boolean allFilled;
    }

    // Called by LWC
    @AuraEnabled(cacheable=false)
    public static OutputWrapper getIntakePrompt(Id intakeId) {
        InputWrapper input = new InputWrapper();
        input.intakeId = intakeId;
        List<OutputWrapper> results = buildPrompt(new List<InputWrapper>{ input });
        return results[0];
    }

    @InvocableMethod(label='Build Intake Prompt' description='Checks required fields on Intake__c and builds a prompt for the human agent to collect missing information.')
    public static List<OutputWrapper> buildPrompt(List<InputWrapper> inputs) {
        List<OutputWrapper> results = new List<OutputWrapper>();

        for (InputWrapper input : inputs) {
            OutputWrapper output = new OutputWrapper();

            Intake__c intake = [
                SELECT
                    Incident_Type__c,
                    Injury_Severity__c,
                    Medical_Treatment_Status__c,
                    Police_Report_Filed__c,
                    Incident_Age__c,
                    Insurance_Available__c,
                    Liability_Clarity__c
                FROM Intake__c
                WHERE Id = :input.intakeId
                LIMIT 1
            ];

            Map<String, String> fieldLabels = new Map<String, String>{
                'Incident_Type__c'            => 'Incident Type',
                'Injury_Severity__c'          => 'Injury Severity',
                'Medical_Treatment_Status__c' => 'Medical Treatment Status',
                'Police_Report_Filed__c'      => 'Police Report Filed',
                'Incident_Age__c'             => 'Incident Age',
                'Insurance_Available__c'      => 'Insurance Available',
                'Liability_Clarity__c'        => 'Liability Clarity'
            };

            Map<String, String> fieldQuestions = new Map<String, String>{
                'Incident_Type__c'            => 'What type of incident occurred? (e.g., auto accident, slip and fall, workplace injury)',
                'Injury_Severity__c'          => 'How severe are the injuries? (e.g., minor, moderate, severe, catastrophic)',
                'Medical_Treatment_Status__c' => 'Has the client received medical treatment? If so, what is the current status?',
                'Police_Report_Filed__c'      => 'Was a police report filed? If yes, do you have the report number?',
                'Incident_Age__c'             => 'When did the incident occur? (date or approximate time frame)',
                'Insurance_Available__c'      => 'Is insurance coverage available? (client\'s own policy or third-party)',
                'Liability_Clarity__c'        => 'How clear is the liability? Is fault established or disputed?'
            };

            List<String> missingFields = new List<String>();

            for (String field : fieldLabels.keySet()) {
                Object val = intake.get(field);
                Boolean isEmpty = (val == null || String.valueOf(val).trim() == '');
                if (isEmpty) {
                    missingFields.add(field);
                }
            }

            output.missingCount = missingFields.size();
            output.allFilled = missingFields.isEmpty();

            if (missingFields.isEmpty()) {
                output.prompt = 'All required intake fields have been completed. No additional information is needed at this time.';
            } else {
                String prompt = 'The following required intake fields are missing. Please ask the client for this information:\n\n';
                Integer idx = 1;
                for (String field : missingFields) {
                    prompt += idx + '. ' + fieldLabels.get(field) + '\n';
                    prompt += '   Question to ask: ' + fieldQuestions.get(field) + '\n\n';
                    idx++;
                }
                prompt += '---\n';
                prompt += 'Once you have collected this information, update the intake record before proceeding.';
                output.prompt = prompt;
            }

            results.add(output);
        }

        return results;
    }
}