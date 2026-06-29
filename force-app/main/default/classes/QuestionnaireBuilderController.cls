public with sharing class QuestionnaireBuilderController {

    @AuraEnabled
    public static Map<String, Object> getQuestionnaireData(String questionnaireId) {
        Map<String, Object> result = new Map<String, Object>();

        List<Question_Node__c> nodes = [
            SELECT Id, Name, Order__c
            FROM   Question_Node__c
            WHERE  Questionnaire__c = :questionnaireId
            ORDER BY Order__c ASC NULLS LAST, Name ASC
        ];
        result.put('nodes', nodes);

        List<Node_Question__c> nodeQuestions = [
            SELECT Id, Question_Node__c, Question__c,
                   Description__c, Mapping__c, Required__c, Order__c
            FROM   Node_Question__c
            WHERE  Questionnaire__c = :questionnaireId
            ORDER BY Order__c ASC NULLS LAST
        ];
        result.put('nodeQuestions', nodeQuestions);

        List<Questionnaire_Navigation__c> navRules = [
            SELECT Id, Source_Node__c, Target_Questionnaire__c,
                   Target_Node__c, Rules_JSON__c, Order__c
            FROM   Questionnaire_Navigation__c
            WHERE  Questionnaire__c = :questionnaireId
            ORDER BY Source_Node__c, Order__c ASC NULLS LAST
        ];
        result.put('navRules', navRules);

        return result;
    }

    @AuraEnabled
    public static List<Question__c> getAllQuestions() {
        return [
            SELECT Id, Name, Question_Text__c, Question_Type__c
            FROM   Question__c
            ORDER BY Question_Text__c ASC NULLS LAST
        ];
    }

    @AuraEnabled
    public static List<Questionnaire__c> getAllQuestionnaires() {
        return [
            SELECT Id, Name
            FROM   Questionnaire__c
            WHERE  Active_Questionnaire__c = true
            ORDER BY Name ASC
        ];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getMappingFields — now returns fieldType so the LWC can filter by it
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<Map<String,String>> getMappingFields() {
        List<Map<String,String>> fields = new List<Map<String,String>>();
        Map<String, Schema.SObjectField> fieldMap =
            Intake__c.SObjectType.getDescribe().fields.getMap();

        List<String> labels = new List<String>();
        Map<String, String> labelToApi  = new Map<String, String>();
        Map<String, String> labelToType = new Map<String, String>();

        for (Schema.SObjectField sfField : fieldMap.values()) {
    Schema.DescribeFieldResult dfr = sfField.getDescribe();
    String apiName = dfr.getName();
            String label     = dfr.getLabel();
            String fieldType = String.valueOf(dfr.getType()).toUpperCase(); // e.g. STRING, DOUBLE, INTEGER, BOOLEAN, DATE, DATETIME, EMAIL, CURRENCY, PERCENT, PHONE, URL, TEXTAREA, PICKLIST, MULTIPICKLIST, REFERENCE
            labels.add(label);
            labelToApi.put(label, apiName);
            labelToType.put(label, fieldType);
        }
        labels.sort();

        for (String label : labels) {
            fields.add(new Map<String,String>{
                'label'     => label,
                'value'     => labelToApi.get(label),
                'fieldType' => labelToType.get(label)
            });
        }
        return fields;
    }

    @AuraEnabled
    public static String saveQuestionnaireData(
        String questionnaireId,
        String name,
        Boolean isActive,
        Boolean isAvailable,
        String nodesJson
    ) {
        try {
            Savepoint sp = Database.setSavepoint();
            try {
                Questionnaire__c q = new Questionnaire__c(
                    Name                       = name,
                    Active_Questionnaire__c    = isActive,
                    Available_Questionnaire__c = isAvailable
                );

                Boolean isNew = String.isBlank(questionnaireId);
                if (!isNew) {
                    q.Id = questionnaireId;
                    update q;
                } else {
                    insert q;
                    questionnaireId = q.Id;
                }

                List<Object> nodesRaw = (List<Object>) JSON.deserializeUntyped(nodesJson);

                if (!isNew) {
                    Set<Id> incomingNodeSfIds = new Set<Id>();
                    for (Object obj : nodesRaw) {
                        Map<String, Object> n = (Map<String, Object>) obj;
                        String sfId = (String) n.get('sfId');
                        if (String.isNotBlank(sfId)) incomingNodeSfIds.add(sfId);
                    }

                    List<Question_Node__c> existingNodes = [
                        SELECT Id FROM Question_Node__c WHERE Questionnaire__c = :questionnaireId
                    ];
                    List<Question_Node__c> toDeleteNodes = new List<Question_Node__c>();
                    for (Question_Node__c en : existingNodes) {
                        if (!incomingNodeSfIds.contains(en.Id)) toDeleteNodes.add(en);
                    }
                    if (!toDeleteNodes.isEmpty()) delete toDeleteNodes;
                }

                Map<Integer, Id> nodeIndexToSfId = new Map<Integer, Id>();
                List<Question_Node__c> nodesToUpsert = new List<Question_Node__c>();
                Integer idx = 0;
                for (Object obj : nodesRaw) {
                    Map<String, Object> n = (Map<String, Object>) obj;
                    String sfId = (String) n.get('sfId');
                    Question_Node__c node = new Question_Node__c(
                        Questionnaire__c = questionnaireId,
                        Name             = (String) n.get('Name'),
                        Order__c         = idx + 1
                    );
                    if (String.isNotBlank(sfId)) node.Id = sfId;
                    nodesToUpsert.add(node);
                    idx++;
                }
                upsert nodesToUpsert;
                for (Integer i = 0; i < nodesToUpsert.size(); i++) {
                    nodeIndexToSfId.put(i, nodesToUpsert[i].Id);
                }

                delete [SELECT Id FROM Node_Question__c          WHERE Questionnaire__c = :questionnaireId];
                delete [SELECT Id FROM Questionnaire_Navigation__c WHERE Questionnaire__c = :questionnaireId];

                List<Node_Question__c>            nqInsert  = new List<Node_Question__c>();
                List<Questionnaire_Navigation__c> navInsert = new List<Questionnaire_Navigation__c>();

                idx = 0;
                for (Object obj : nodesRaw) {
                    Map<String, Object> n = (Map<String, Object>) obj;
                    Id nodeSfId = nodeIndexToSfId.get(idx);

                    List<Object> questions = (List<Object>) n.get('questions');
                    if (questions != null) {
                        Integer qOrder = 1;
                        for (Object qObj : questions) {
                            Map<String, Object> qMap = (Map<String, Object>) qObj;
                            String qId = (String) qMap.get('questionId');
                            if (String.isNotBlank(qId)) {
                                nqInsert.add(new Node_Question__c(
                                    Questionnaire__c = questionnaireId,
                                    Question_Node__c = nodeSfId,
                                    Question__c      = qId,
                                    Description__c   = (String)  qMap.get('description'),
                                    Mapping__c       = (String)  qMap.get('mapping'),
                                    Required__c      = (Boolean) qMap.get('required'),
                                    Order__c         = qOrder++
                                ));
                            }
                        }
                    }

                    List<Object> navRules = (List<Object>) n.get('navRules');
                    if (navRules != null) {
                        Integer navOrder = 1;
                        for (Object navObj : navRules) {
                            Map<String, Object> nav = (Map<String, Object>) navObj;
                            String targetNId = (String) nav.get('targetNodeId');
                            Object targetIdxObj = nav.get('targetNodeIndex');
                            if (targetIdxObj != null) {
                                Integer targetIdx = ((Decimal) targetIdxObj).intValue();
                                if (nodeIndexToSfId.containsKey(targetIdx)) {
                                    targetNId = nodeIndexToSfId.get(targetIdx);
                                }
                            }
                            String rulesJson = (String) nav.get('rulesJson');
                            if (String.isNotBlank(targetNId)) {
                                navInsert.add(new Questionnaire_Navigation__c(
                                    Questionnaire__c        = questionnaireId,
                                    Source_Node__c          = nodeSfId,
                                    Target_Questionnaire__c = questionnaireId,
                                    Target_Node__c          = targetNId,
                                    Rules_JSON__c           = rulesJson,
                                    Order__c                = navOrder++
                                ));
                            }
                        }
                    }
                    idx++;
                }

                if (!nqInsert.isEmpty())  insert nqInsert;
                if (!navInsert.isEmpty()) insert navInsert;

                return questionnaireId;

            } catch (Exception e) {
                Database.rollback(sp);
                throw new AuraHandledException(e.getMessage());
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}