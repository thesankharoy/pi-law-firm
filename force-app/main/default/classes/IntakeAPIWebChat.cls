@RestResource(urlMapping='/intakefromWeb')
global with sharing class IntakeAPIWebChat {

    global class IntakeRequest {
        public String intakeSummary;
    }

    @HttpPost
    global static String createIntake() {

        RestRequest req = RestContext.request;

        IntakeRequest input =
            (IntakeRequest)JSON.deserialize(
                req.requestBody.toString(),
                IntakeRequest.class
            );
        
                // Debug deserialized value
        System.debug('=== Intake Summary Received ===');
        System.debug(input.intakeSummary);

        Map<String, Object> flowInputs =
            new Map<String, Object>();

        flowInputs.put(
            'varIntakeSummary',
            input.intakeSummary
        );

        Flow.Interview.PI_WebChat_To_Intake interview =
            new Flow.Interview.PI_WebChat_To_Intake(
                flowInputs
            );

        interview.start();

        return 'Success';
    }
}