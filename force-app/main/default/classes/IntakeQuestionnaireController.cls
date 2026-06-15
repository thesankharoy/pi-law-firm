public with sharing class IntakeQuestionnaireController {

    @AuraEnabled(cacheable=true)
    public static List<Questionnaire__c> getAvailableQuestionnaires(String caseType) {
        return [
            //  SELECT Id, Name, Case_Type__c, Is_Default__c
            //  FROM Questionnaire__c
             SELECT Id, Name, Is_Default__c
             FROM Questionnaire__c
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Question__c> getQuestions(String questionnaireId) {
        return [
            SELECT Id, Question_Text__c, Question_Type__c, Order__c,
                   Section__c
            FROM Question__c
            WHERE Questionnaire__c = :questionnaireId
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Intake_Response__c> getExistingResponses(String intakeId, String questionnaireId) {
        return [
            SELECT Id, Question__c, Response_Text__c
            FROM Intake_Response__c
            WHERE Intake__c = :intakeId
            AND Questionnaire__c = :questionnaireId
        ];
    }

    @AuraEnabled
    public static String saveResponses(String intakeId, String questionnaireId, String responsesJson) {
        try {
            List<Map<String, String>> responseMaps = (List<Map<String, String>>) JSON.deserialize(
                responsesJson, List<Map<String, String>>.class
            );

            List<Intake_Response__c> oldResponses = [
                SELECT Id FROM Intake_Response__c
                WHERE Intake__c = :intakeId AND Questionnaire__c = :questionnaireId
            ];
            delete oldResponses;

            List<Intake_Response__c> newResponses = new List<Intake_Response__c>();
            for (Map<String, String> r : responseMaps) {
                if (String.isNotBlank(r.get('responseText'))) {
                    newResponses.add(new Intake_Response__c(
                        Intake__c = intakeId,
                        Question__c = r.get('questionId'),
                        Questionnaire__c = questionnaireId,
                        Response_Text__c = r.get('responseText')
                    ));
                }
            }
            insert newResponses;
            return 'SUCCESS';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
public static Intake_Response__c getSavedQuestionnaireId(String intakeId) {
    List<Intake_Response__c> resp = [
        SELECT Id, Questionnaire__c
        FROM Intake_Response__c
        WHERE Intake__c = :intakeId
        LIMIT 1
    ];
    return resp.isEmpty() ? null : resp[0];
}
}