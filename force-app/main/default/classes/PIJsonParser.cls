public class PIJsonParser {

    public class Input {
        @InvocableVariable(required=true)
        public String jsonResponse;
    }

    public class Output {
        @InvocableVariable
        public String firstName;

        @InvocableVariable
        public String lastName;

        @InvocableVariable
        public String email;

        @InvocableVariable
        public String phone;

        @InvocableVariable
        public String accidentAge;

        @InvocableVariable
        public String accidentType;

        @InvocableVariable
        public String injurySeverity;

        @InvocableVariable
        public String insuranceAvailable;

        @InvocableVariable
        public String liabilityClarity;

        @InvocableVariable
        public String medicalTreatmentStarted;

        @InvocableVariable
        public String policeReportAvailable;

        @InvocableVariable
        public String description;

        @InvocableVariable
        public String summary;
    }

    @InvocableMethod(label='Parse PI JSON Response')
    public static List<Output> parseJson(List<Input> inputs) {

        List<Output> results = new List<Output>();

        for(Input input : inputs) {

            Map<String,Object> data =
                (Map<String,Object>)JSON.deserializeUntyped(input.jsonResponse);

            Output o = new Output();

            o.firstName = (String)data.get('firstName');
            o.lastName = (String)data.get('lastName');
            o.email = (String)data.get('email');
            o.phone = (String)data.get('phone');
            o.accidentAge = (String)data.get('accidentAge');
            o.accidentType = (String)data.get('accidentType');
            o.injurySeverity = (String)data.get('injurySeverity');
            o.insuranceAvailable = (String)data.get('insuranceAvailable');
            o.liabilityClarity = (String)data.get('liabilityClarity');
            o.medicalTreatmentStarted = (String)data.get('medicalTreatmentStarted');
            o.policeReportAvailable = (String)data.get('policeReportAvailable');
            o.description = (String)data.get('description');
            o.summary = (String)data.get('summary');

            results.add(o);
        }

        return results;
    }
}