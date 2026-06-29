public class PIJsonParser {

    public class Input {
        @InvocableVariable(required=true)
        public String jsonResponse;
    }

    public class Output {

        @InvocableVariable public String firstName;
        @InvocableVariable public String lastName;
        @InvocableVariable public String email;
        @InvocableVariable public String phone;
        @InvocableVariable public String incidentDate;
        @InvocableVariable public String accidentAge;
        @InvocableVariable public String accidentType;
        @InvocableVariable public String injurySeverity;
        @InvocableVariable public String insuranceAvailable;
        @InvocableVariable public String liabilityClarity;
        @InvocableVariable public String medicalTreatmentStarted;
        @InvocableVariable public String policeReportAvailable;
        @InvocableVariable public String description;
        @InvocableVariable public String summary;
        @InvocableVariable public String errorMessage;
    }

    @InvocableMethod(label='Parse PI JSON Response')
    public static List<Output> parseJson(List<Input> inputs) {

        List<Output> results = new List<Output>();

        for(Input input : inputs){

            Output o = new Output();

            try{

                String jsonText = input.jsonResponse;

                System.debug('===== RAW RESPONSE =====');
                System.debug(jsonText);

                if(String.isBlank(jsonText)){
                    o.errorMessage = 'Input JSON is empty.';
                    results.add(o);
                    continue;
                }

                // Remove markdown code fences
                jsonText = jsonText.replace('```json','');
                jsonText = jsonText.replace('```JSON','');
                jsonText = jsonText.replace('```','');
                jsonText = jsonText.trim();

                // Extract JSON object only
                Integer startPos = jsonText.indexOf('{');
                Integer endPos = jsonText.lastIndexOf('}');

                if(startPos >= 0 && endPos >= startPos){
                    jsonText = jsonText.substring(startPos, endPos + 1);
                }

                System.debug('===== CLEAN JSON =====');
                System.debug(jsonText);

                // IMPORTANT: JSON (capital letters), NOT jsonText.deserializeUntyped(...)
                Map<String,Object> data =
                    (Map<String,Object>) JSON.deserializeUntyped(jsonText);

                o.firstName = (String)data.get('firstName');
                o.lastName = (String)data.get('lastName');
                o.email = (String)data.get('email');
                o.phone = (String)data.get('phone');
                o.incidentDate = (String)data.get('incidentDate');
                o.accidentAge = (String)data.get('accidentAge');
                o.accidentType = (String)data.get('accidentType');
                o.injurySeverity = (String)data.get('injurySeverity');
                o.insuranceAvailable = (String)data.get('insuranceAvailable');
                o.liabilityClarity = (String)data.get('liabilityClarity');
                o.medicalTreatmentStarted = (String)data.get('medicalTreatmentStarted');
                o.policeReportAvailable = (String)data.get('policeReportAvailable');
                o.description = (String)data.get('description');
                o.summary = (String)data.get('summary');

            }
            catch(Exception ex){

                o.errorMessage = ex.getMessage();

                System.debug('===== ERROR =====');
                System.debug(ex.getMessage());
                System.debug(ex.getStackTraceString());
            }

            results.add(o);
        }

        return results;
    }
}