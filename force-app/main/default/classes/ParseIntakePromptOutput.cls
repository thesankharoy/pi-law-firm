public class ParseIntakePromptOutput {

    public class InputVars {
        @InvocableVariable(required=true)
        public String promptJson;
    }

    public class OutputVars {
        @InvocableVariable public String incidentType;
        @InvocableVariable public String injurySeverity;
        @InvocableVariable public String medicalTreatment;
        @InvocableVariable public String policeReport;
        @InvocableVariable public String incidentAge;
        @InvocableVariable public String insurance;
        @InvocableVariable public String liability;
    }

    @InvocableMethod(label='Parse Intake Prompt Output')
    public static List<OutputVars> parse(List<InputVars> inputs) {
        List<OutputVars> results = new List<OutputVars>();

        for (InputVars input : inputs) {
            OutputVars out = new OutputVars();
            try {
                String clean = input.promptJson
                    .replaceAll('```json', '')
                    .replaceAll('```', '')
                    .trim();

                Map<String, Object> data =
                    (Map<String, Object>) JSON.deserializeUntyped(clean);

                out.incidentType     = getString(data, 'incidentType');
                out.injurySeverity   = getString(data, 'injurySeverity');
                out.medicalTreatment = getString(data, 'medicalTreatment');
                out.policeReport     = getString(data, 'policeReport');
                out.incidentAge      = getString(data, 'incidentAge');
                out.insurance        = getString(data, 'insurance');
                out.liability        = getString(data, 'liability');

            } catch (Exception e) {
                System.debug('ParseIntakePromptOutput error: ' + e.getMessage());
            }
            results.add(out);
        }
        return results;
    }

    private static String getString(Map<String, Object> data, String key) {
        Object val = data.get(key);
        return val != null ? String.valueOf(val).trim() : '';
    }
}