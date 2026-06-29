public without sharing class IntakeConversationService {

    public static String buildConversation(Id intakeId) {

        Intake__c c = [
            SELECT Id, Intake_Phone__c, Client__r.MobilePhone, Client__r.Phone
            FROM Intake__c
            WHERE Id = :intakeId
        ];

        String phone = String.isNotBlank(c.Intake_Phone__c)
            ? c.Intake_Phone__c
            : String.isNotBlank(c.Client__r.MobilePhone)
                ? c.Client__r.MobilePhone
                : c.Client__r.Phone;

        if (String.isBlank(phone)) return null;

        List<TwilioSF__Message__c> msgs = [
            SELECT TwilioSF__Body__c,
                   TwilioSF__From_Number__c,
                   TwilioSF__To_Number__c,
                   CreatedDate
            FROM TwilioSF__Message__c
            WHERE TwilioSF__From_Number__c = :phone
               OR TwilioSF__To_Number__c   = :phone
            ORDER BY CreatedDate ASC
            LIMIT 200
        ];

        String transcript = '';

        for (TwilioSF__Message__c msg : msgs) {
            String speaker = msg.TwilioSF__From_Number__c == phone ? 'Client' : 'Agent';
            transcript += '[' + msg.CreatedDate.format('yyyy-MM-dd HH:mm') + '] '
                        + speaker + ': '
                        + msg.TwilioSF__Body__c + '\n';
        }

        return transcript;
    }
}