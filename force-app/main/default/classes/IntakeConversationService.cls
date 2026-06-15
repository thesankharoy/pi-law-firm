public with sharing class IntakeConversationService {

    public static String buildConversation(Id intakeId){

        Intake__c c = [
            SELECT Id,
                   Employer_Phone__c
            FROM Intake__c
            WHERE Id = :intakeId
        ];

        String phone = c.Employer_Phone__c;

        if(String.isBlank(phone)){
            return null;
        }

        List<TwilioSF__Message__c> msgs = [
            SELECT
                TwilioSF__Body__c,
                TwilioSF__From_Number__c,
                TwilioSF__To_Number__c,
                CreatedDate
            FROM TwilioSF__Message__c
            WHERE TwilioSF__From_Number__c = :phone
               OR TwilioSF__To_Number__c = :phone
            ORDER BY CreatedDate ASC
            LIMIT 100
        ];

        String transcript = '';

        for(TwilioSF__Message__c msg : msgs){

            String speaker =
                msg.TwilioSF__From_Number__c == phone
                ? 'Client'
                : 'Agent';

            transcript +=
                '[' + msg.CreatedDate.format() + '] '
                + speaker
                + ': '
                + msg.TwilioSF__Body__c
                + '\n';
        }

        return transcript;
    }
}