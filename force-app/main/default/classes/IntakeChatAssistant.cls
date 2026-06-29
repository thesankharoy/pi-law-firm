public with sharing class IntakeChatAssistant {

    @AuraEnabled
    public static String askAssistant(String recordId, String userQuestion, String conversationHistory) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('No Intake record context.');
            }

            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();

            ConnectApi.EinsteinLlmAdditionalConfigInput config =
                new ConnectApi.EinsteinLlmAdditionalConfigInput();
            config.applicationName = 'PromptBuilderPreview';
            input.additionalConfig = config;
            input.isPreview = false;

            Map<String, ConnectApi.WrappedValue> params =
                new Map<String, ConnectApi.WrappedValue>();

            // Free-text inputs → plain string
            ConnectApi.WrappedValue q = new ConnectApi.WrappedValue();
            q.value = userQuestion;
            params.put('Input:userQuestion', q);

            ConnectApi.WrappedValue hist = new ConnectApi.WrappedValue();
            hist.value = String.isBlank(conversationHistory) ? 'No prior messages.' : conversationHistory;
            params.put('Input:conversationHistory', hist);

            // Object/record input → Map with 'id'
            ConnectApi.WrappedValue rec = new ConnectApi.WrappedValue();
            Map<String, Object> recMap = new Map<String, Object>();
            recMap.put('id', recordId);
            rec.value = recMap;
            params.put('Input:Intake', rec);

            input.inputParams = params;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('Intake_Chat_Assistant', input);

            if (response != null && response.generations != null && !response.generations.isEmpty()) {
                return response.generations[0].text;
            }
            return 'No response was generated.';

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}