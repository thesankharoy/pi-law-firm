public with sharing class Questioneditorcontroller {

    // ─────────────────────────────────────────────────────────────────────────
    // Answer Type options — pulled live from the Question_Type__c picklist,
    // so whatever values you've configured on the field (STRING, INTEGER,
    // SELECT, MULTISELECT, BOOLEAN, DATE, DATETIME, DECIMAL, LOOKUP, EMAIL...)
    // show up automatically without hardcoding them here.
    // ─────────────────────────────────────────────────────────────────────────
    // @AuraEnabled(cacheable=true)
    // public static List<Map<String, String>> getAnswerTypeOptions() {
    //     List<Map<String, String>> options = new List<Map<String, String>>();

    //     Schema.DescribeFieldResult fieldResult = Question__c.Question_Type__c.getDescribe();
    //     List<Schema.PicklistEntry> entries = fieldResult.getPicklistValues();

    //     for (Schema.PicklistEntry entry : entries) {
    //         if (entry.isActive()) {
    //             options.add(new Map<String, String>{
    //                 'label' => entry.getLabel(),
    //                 'value' => entry.getValue()
    //             });
    //         }
    //     }
    //     return options;
    // }

    @AuraEnabled(cacheable=true)
public static List<Map<String, String>> getAnswerTypeOptions() {
    return new List<Map<String, String>>{
        new Map<String,String>{ 'label' => 'Checkbox',               'value' => 'Checkbox'    },
        new Map<String,String>{ 'label' => 'Currency',               'value' => 'CURRENCY'    },
        new Map<String,String>{ 'label' => 'Date',                   'value' => 'Date'        },
        new Map<String,String>{ 'label' => 'Date/Time',              'value' => 'DATETIME'    },
        new Map<String,String>{ 'label' => 'Email',                  'value' => 'Email'       },
        new Map<String,String>{ 'label' => 'Number',                 'value' => 'Number'      },
        new Map<String,String>{ 'label' => 'Percent',                'value' => 'PERCENT'     },
        new Map<String,String>{ 'label' => 'Phone',                  'value' => 'Phone'       },
        new Map<String,String>{ 'label' => 'Picklist',               'value' => 'Picklist'    },
        new Map<String,String>{ 'label' => 'Picklist (Multi-Select)','value' => 'Multiselect' },
        new Map<String,String>{ 'label' => 'Text',                   'value' => 'Text'        },
        new Map<String,String>{ 'label' => 'Text Area',              'value' => 'Textarea'    },
        new Map<String,String>{ 'label' => 'Text Area (Long)',       'value' => 'TEXTAREA_LONG'},
        new Map<String,String>{ 'label' => 'Text Area (Rich)',       'value' => 'TEXTAREA_RICH'},
        new Map<String,String>{ 'label' => 'Text (Encrypted)',       'value' => 'ENCRYPTED'   },
        new Map<String,String>{ 'label' => 'Time',                   'value' => 'TIME'        },
        new Map<String,String>{ 'label' => 'URL',                    'value' => 'URL'         },
        new Map<String,String>{ 'label' => 'Address',                'value' => 'ADDRESS'     }
    };
}

    @AuraEnabled
public static Question__c getQuestion(Id questionId) {
    return [
        SELECT Id, Name, Question_Text__c, Question_Type__c, Questionnaire__c, Picklist_Options__c
        FROM   Question__c
        WHERE  Id = :questionId
    ];
}

    // ─────────────────────────────────────────────────────────────────────────
    // Save a new Question__c.
    // Name is required on the object, so it's auto-set from the label
    // (truncated to 80 chars, the field's max length).
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
public static Id saveQuestion(String questionId, String questionLabel, String answerType, String questionnaireId, String picklistOptions) {
    try {
        String autoName = questionLabel.length() > 80
            ? questionLabel.substring(0, 80)
            : questionLabel;

        Question__c q = new Question__c(
            Name             = autoName,
            Question_Text__c = questionLabel,
            Question_Type__c = answerType,
            // Questionnaire__c = questionnaireId,
            Picklist_Options__c  = picklistOptions
        );

        if (String.isNotBlank(questionId)) {
            q.Id = questionId;
            update q;
        } else {
            insert q;
        }
        return q.Id;

    } catch (Exception e) {
        throw new AuraHandledException(e.getMessage());
    }
}
}