public with sharing class BuildConversationTranscript {

    public class Request {
        @InvocableVariable(required=true)
        public Id intakeId;
    }

    public class Response {
        @InvocableVariable
        public String transcript;
    }

    @InvocableMethod(label='Build Conversation Transcript')
    public static List<Response> build(List<Request> requests) {

        List<Response> results = new List<Response>();

        Set<Id> intakeIds = new Set<Id>();

        for(Request req : requests){
            if(req.intakeId != null){
                intakeIds.add(req.intakeId);
            }
        }

        Map<Id, Intake__c> intakeMap = new Map<Id, Intake__c>(
            [
                SELECT Id, Employer_Phone__c
                FROM Intake__c
                WHERE Id IN :intakeIds
            ]
        );

        for(Request req : requests){

            String transcript = '';

            Intake__c intakeRec = intakeMap.get(req.intakeId);

            if(intakeRec != null &&
               !String.isBlank(intakeRec.Employer_Phone__c)){

                String phone = intakeRec.Employer_Phone__c;

                List<TwilioSF__Message__c> messages = [
                    SELECT
                        TwilioSF__Body__c,
                        TwilioSF__From_Number__c,
                        TwilioSF__To_Number__c,
                        CreatedDate
                    FROM TwilioSF__Message__c
                    WHERE TwilioSF__From_Number__c = :phone
                       OR TwilioSF__To_Number__c = :phone
                    ORDER BY CreatedDate
                ];

                for(TwilioSF__Message__c msg : messages){

                    String direction =
                        msg.TwilioSF__From_Number__c == phone
                        ? 'Client'
                        : 'Agent';

                    transcript +=
                        '[' + String.valueOf(msg.CreatedDate) + '] '
                        + direction + ': '
                        + (msg.TwilioSF__Body__c == null
                            ? ''
                            : msg.TwilioSF__Body__c)
                        + '\n';
                }
            }

            Response r = new Response();
            r.transcript = transcript;
            results.add(r);
        }

        return results;
    }
}