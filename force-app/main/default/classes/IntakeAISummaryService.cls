public with sharing class IntakeAISummaryService {


    @AuraEnabled(cacheable=true)
    public static Intake__c getSummary(Id intakeId) {

        if (intakeId == null) {

            throw new AuraHandledException(
                'Intake Id is required.'
            );
        }

        return [

            SELECT
                AI_Conversation_Summary__c,
                AI_Sentiment__c,
                AI_Next_Recommended_Action__c,
                AI_Next_Message__c,
                Transcript__c

            FROM Intake__c

            WHERE Id = :intakeId

            LIMIT 1
        ];
    }

}