public with sharing class IntakeQuestionnaireController {

    @AuraEnabled
public static Questionnaire__c getAutoQuestionnaire(String intakeId) {
    List<Intake__c> intakes = [
        SELECT Incident_Type__c
        FROM   Intake__c
        WHERE  Id = :intakeId
        LIMIT  1
    ];
    if (intakes.isEmpty() || String.isBlank(intakes[0].Incident_Type__c)) {
        return null;
    }
    String incidentType = intakes[0].Incident_Type__c;
    List<Questionnaire__c> matches = [
        SELECT Id, Name
        FROM   Questionnaire__c
        WHERE  Name                    = :incidentType
        AND    Active_Questionnaire__c = true
        AND    Available_Questionnaire__c = true
        LIMIT  1
    ];
    return matches.isEmpty() ? null : matches[0];
}
    
    @AuraEnabled
    public static List<Questionnaire__c> getAvailableQuestionnaires(String caseType) {
        return [
            SELECT Id, Name, Is_Default__c, Active_Questionnaire__c, Available_Questionnaire__c
            FROM   Questionnaire__c
            WHERE  Active_Questionnaire__c = true
            AND    Available_Questionnaire__c = true
            ORDER BY Name
        ];
    }

    
    @AuraEnabled
public static Questionnaire__c getSavedQuestionnaire(String intakeId) {
    List<Intake__c> intakes = [
        SELECT Questionnaire__c, Questionnaire__r.Id, Questionnaire__r.Name
        FROM   Intake__c
        WHERE  Id = :intakeId
        LIMIT  1
    ];
    if (intakes.isEmpty() || intakes[0].Questionnaire__c == null) {
        return null;
    }
    return intakes[0].Questionnaire__r;
}
    
    @AuraEnabled
    public static List<Question_Node__c> getQuestionNodes(String questionnaireId) {
        return [
            SELECT Id, Name, Order__c
            FROM   Question_Node__c
            WHERE  Questionnaire__c = :questionnaireId
            ORDER BY Order__c ASC NULLS LAST, Name ASC
        ];
    }

  
    @AuraEnabled
public static List<Map<String, Object>> getQuestions(String questionnaireId) {
    List<Map<String, Object>> result = new List<Map<String, Object>>();

    List<Node_Question__c> nodeQuestions = [
    SELECT  Question_Node__c,
            Question__c,
            Question__r.Question_Text__c,
            Question__r.Question_Type__c,
            Question__r.Picklist_Options__c,
            Question__r.Is_Conditional__c,
            Question__r.Condition_Question__c,
            Question__r.Condition_Value__c,
            Description__c,
            Mapping__c,
            Required__c,
            Order__c
    FROM    Node_Question__c
    WHERE   Questionnaire__c = :questionnaireId
    ORDER BY Question_Node__c, Order__c ASC NULLS LAST
];

for (Node_Question__c nq : nodeQuestions) {
    result.add(new Map<String, Object>{
        'Id'                    => nq.Question__c,
        'Question_Node__c'      => nq.Question_Node__c,
        'Question_Text__c'      => nq.Question__r.Question_Text__c,
        'Question_Type__c'      => nq.Question__r.Question_Type__c,
        'Picklist_Options__c'   => nq.Question__r.Picklist_Options__c,
        'Is_Conditional__c'     => nq.Question__r.Is_Conditional__c,
        'Condition_Question__c' => nq.Question__r.Condition_Question__c,
        'Condition_Value__c'    => nq.Question__r.Condition_Value__c,
        'Description__c'        => nq.Description__c,
        'Mapping__c'            => nq.Mapping__c,
        'Is_Required__c'        => nq.Required__c,
        'Order__c'              => nq.Order__c
    });
}
return result;
}

 
    @AuraEnabled
    public static List<Intake_Response__c> getExistingResponses(String intakeId, String questionnaireId) {
        return [
            SELECT Id, Question__c, Response_Text__c
            FROM   Intake_Response__c
            WHERE  Intake__c          = :intakeId
            AND    Questionnaire__c   = :questionnaireId
        ];
    }


    @AuraEnabled
public static List<Questionnaire_Navigation__c> getNavigationRules(String questionnaireId) {
    return [
        SELECT  Id,
                Source_Node__c,
                Source_Node__r.Name,
                Target_Questionnaire__c,
                Target_Questionnaire__r.Name,
                Target_Node__c,
                Target_Node__r.Name,
                Rules_JSON__c,
                Order__c
        FROM    Questionnaire_Navigation__c
        WHERE   Questionnaire__c = :questionnaireId
        ORDER BY Source_Node__c, Order__c ASC NULLS LAST
    ];
}

@AuraEnabled
public static String saveResponses(
    String intakeId,
    String questionnaireId,
    String responsesJson
) {
    try {
        List<Object> responseMapsRaw = (List<Object>) JSON.deserializeUntyped(responsesJson);

        // Delete old responses for this intake + questionnaire
        List<Intake_Response__c> oldResponses = [
            SELECT Id
            FROM   Intake_Response__c
            WHERE  Intake__c        = :intakeId
            AND    Questionnaire__c = :questionnaireId
        ];
        if (!oldResponses.isEmpty()) {
            delete oldResponses;
        }

        // Insert new responses + collect mapped fields for the Intake__c update
        List<Intake_Response__c> newResponses = new List<Intake_Response__c>();
        Intake__c intakeUpdate = new Intake__c(Id = intakeId, Questionnaire__c = questionnaireId);

        Map<String, Schema.SObjectField> intakeFieldMap =
            Intake__c.SObjectType.getDescribe().fields.getMap();

        for (Object rObj : responseMapsRaw) {
            Map<String, Object> r = (Map<String, Object>) rObj;

            String questionId   = (String) r.get('questionId');
            String responseText = (String) r.get('responseText');
            String mappingField = (String) r.get('mappingField');

            if (String.isBlank(responseText)) continue;

            newResponses.add(new Intake_Response__c(
                Intake__c        = intakeId,
                Questionnaire__c = questionnaireId,
                Question__c      = questionId,
                Response_Text__c = responseText
            ));

            if (String.isNotBlank(mappingField) && intakeFieldMap.containsKey(mappingField)) {
                Object convertedValue = convertValueForField(
                    intakeFieldMap.get(mappingField),
                    responseText
                );
                if (convertedValue != null) {
                    intakeUpdate.put(mappingField, convertedValue);
                }
            }
        }

        if (!newResponses.isEmpty()) {
            insert newResponses;
        }

        update intakeUpdate;

        return 'SUCCESS';

    } catch (Exception e) {
        throw new AuraHandledException(e.getMessage());
    }
}

private static Object convertValueForField(Schema.SObjectField field, String rawValue) {
    Schema.DisplayType fieldType = field.getDescribe().getType();

    if (fieldType == Schema.DisplayType.ADDRESS) {
        return null;
    }

    try {
       switch on fieldType {
    when INTEGER {
        return Integer.valueOf(rawValue);
    }
    when DOUBLE, CURRENCY, PERCENT {
        return Decimal.valueOf(rawValue);
    }
    when BOOLEAN {
        return Boolean.valueOf(rawValue);
    }
    when DATE {
        return Date.valueOf(rawValue);
    }
    when DATETIME {
        return DateTime.valueOf(rawValue);
    }
    when TIME {
        List<String> parts = rawValue.split(':');
        Integer h = Integer.valueOf(parts[0]);
        Integer m = Integer.valueOf(parts[1]);
        Integer s = parts.size() > 2 ? Integer.valueOf(parts[2].split('\\.')[0]) : 0;
        return Time.newInstance(h, m, s, 0);
    }
    when MULTIPICKLIST {
        return rawValue;
    }
    when else {
        return rawValue;
    }
}
    } catch (Exception e) {
        return null;
    }
}

}