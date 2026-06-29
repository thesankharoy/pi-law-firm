public with sharing class IntakeClaudeChat {

    private static final String NAMED_CRED = 'callout:Anthropic_Claude';
    private static final String MODEL = 'claude-opus-4-8';
    private static final Integer MAX_TURNS = 8;   // schema discovery may take a few turns

    @AuraEnabled
    public static String askAssistant(String recordId, String userQuestion, String conversationHistory) {
        System.debug('=== IntakeClaudeChat START === q: ' + userQuestion);
        try {
            String systemPrompt = buildSystemPrompt(recordId, conversationHistory);
            List<Object> messages = new List<Object>{ msg('user', userQuestion) };

            for (Integer turn = 0; turn < MAX_TURNS; turn++) {
                Map<String, Object> parsed = callClaude(systemPrompt, messages);
                String stopReason    = (String) parsed.get('stop_reason');
                List<Object> content = (List<Object>) parsed.get('content');
                System.debug('turn ' + turn + ' stop_reason: ' + stopReason);

                if (stopReason == 'tool_use') {
                    messages.add(new Map<String, Object>{ 'role' => 'assistant', 'content' => content });
                    List<Object> toolResults = new List<Object>();
                    for (Object blkObj : content) {
                        Map<String, Object> blk = (Map<String, Object>) blkObj;
                        if (blk.get('type') == 'tool_use') {
                            String toolName = (String) blk.get('name');
                            Map<String, Object> toolInput = (Map<String, Object>) blk.get('input');
                            System.debug('Tool: ' + toolName + ' input: ' + JSON.serialize(toolInput));
                            String result = ToolExecutor.run(toolName, toolInput);
                            System.debug('Result: ' + result);
                            toolResults.add(new Map<String, Object>{
                                'type' => 'tool_result', 'tool_use_id' => blk.get('id'), 'content' => result
                            });
                        }
                    }
                    messages.add(new Map<String, Object>{ 'role' => 'user', 'content' => toolResults });
                    continue;
                }

                return extractText(content);
            }
            return 'I could not complete that in time — please try rephrasing.';

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static Map<String, Object> callClaude(String systemPrompt, List<Object> messages) {
        Map<String, Object> body = new Map<String, Object>{
            'model' => MODEL, 'max_tokens' => 4096, 'system' => systemPrompt,
            'tools' => tools(), 'messages' => messages
        };
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CRED + '/v1/messages');
        req.setMethod('POST');
        req.setHeader('content-type', 'application/json');
        req.setHeader('anthropic-version', '2023-06-01');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(body));

        HttpResponse res = new Http().send(req);
        System.debug('Claude status: ' + res.getStatusCode());
        if (res.getStatusCode() != 200) {
            System.debug(LoggingLevel.ERROR, 'Claude body: ' + res.getBody());
            throw new CalloutException('Claude API error ' + res.getStatusCode() + ': ' + res.getBody());
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    private static List<Object> tools() {
        return new List<Object>{
            new Map<String, Object>{
                'name' => 'list_objects',
                'description' => 'Discover Salesforce objects the user can query. Pass a keyword in "filter" to narrow (e.g. "intake", "task"). Returns API names and labels.',
                'input_schema' => new Map<String, Object>{
                    'type' => 'object',
                    'properties' => new Map<String, Object>{
                        'filter' => new Map<String, Object>{ 'type' => 'string', 'description' => 'Keyword to match in object API name or label (optional).' }
                    }
                }
            },
            new Map<String, Object>{
                'name' => 'describe_object',
                'description' => 'List the fields (API name, label, type) of a Salesforce object so you can build a correct SOQL query.',
                'input_schema' => new Map<String, Object>{
                    'type' => 'object',
                    'properties' => new Map<String, Object>{
                        'objectApiName' => new Map<String, Object>{ 'type' => 'string', 'description' => 'API name, e.g. Intake__c or Contact.' }
                    },
                    'required' => new List<String>{ 'objectApiName' }
                }
            },
            new Map<String, Object>{
                'name' => 'soql_query',
                'description' => 'Run a read-only SOQL SELECT and return rows (max 200). Results are limited to what the current user can access. Use COUNT(Id) total for counts and GROUP BY for breakdowns; always alias aggregate functions.',
                'input_schema' => new Map<String, Object>{
                    'type' => 'object',
                    'properties' => new Map<String, Object>{
                        'soql' => new Map<String, Object>{ 'type' => 'string', 'description' => 'A SOQL SELECT statement. Must start with SELECT.' }
                    },
                    'required' => new List<String>{ 'soql' }
                }
            },
            new Map<String, Object>{
                'name' => 'run_report',
                'description' => 'Run a saved Salesforce report by its developer name and return its grand total and link.',
                'input_schema' => new Map<String, Object>{
                    'type' => 'object',
                    'properties' => new Map<String, Object>{
                        'reportDeveloperName' => new Map<String, Object>{ 'type' => 'string', 'description' => 'API/developer name of the saved report.' }
                    },
                    'required' => new List<String>{ 'reportDeveloperName' }
                }
            },
            new Map<String, Object>{
                'name' => 'faq_lookup',
                'description' => 'Look up the firm\'s APPROVED objection-handling playbook (FAQ knowledge base) for the recommended response to a client objection or question. Use this whenever the user asks how to handle an objection, what to say to a client, or for the best response/script for a situation. Pass objectionType for a known category, or a free-text keyword.',
                'input_schema' => new Map<String, Object>{
                    'type' => 'object',
                    'properties' => new Map<String, Object>{
                        'objectionType' => new Map<String, Object>{ 'type' => 'string', 'description' => 'Optional objection category, e.g. Fee_Percentage, Need_To_Think, Already_Talked_To_Firm, Why_Your_Firm, Distrust.' },
                        'keyword' => new Map<String, Object>{ 'type' => 'string', 'description' => 'Optional free text to match entry titles/responses, e.g. "fee", "think about it".' }
                    }
                }
            },
            new Map<String, Object>{
                'name' => 'conversion_forecast',
                'description' => 'Get the firm\'s latest conversion forecast: projected signed cases and value for the next 30/60/90 days, with confidence bands and a driver narrative. Use for "how many will we sign", "what is the forecast / pipeline outlook", "are we on track".',
                'input_schema' => new Map<String, Object>{ 'type' => 'object', 'properties' => new Map<String, Object>{} }
            },
            new Map<String, Object>{
                'name' => 'source_quality',
                'description' => 'Get lead sources ranked by quality (sign rate, cost-per-signed-case, ROI score) plus the latest per-source signing forecast. Use for "which marketing source is best/worst", "where should we spend", "cost per signed case by source".',
                'input_schema' => new Map<String, Object>{ 'type' => 'object', 'properties' => new Map<String, Object>{} }
            }
        };
    }

    private static String buildSystemPrompt(String recordId, String conversationHistory) {
        String s =
            'You are an AI data assistant for a personal injury (PI) law firm\'s Salesforce org. ' +
            'You can read ANY data the current user is permitted to see, using your tools.\n' +
            'Workflow: if you are unsure of an object or field API name, call list_objects and/or ' +
            'describe_object FIRST, then build a correct SOQL query and call soql_query. ' +
            'Always answer counts, lists, and totals from tool results — never invent data.\n' +
            'SOQL tips: for "how many" use SELECT COUNT(Id) total FROM Object [WHERE ...]; ' +
            'for breakdowns use SELECT Field, COUNT(Id) total FROM Object GROUP BY Field; ' +
            'always alias aggregate functions; add LIMIT for record lists.\n' +
            'Key schema: Intake__c is the intake/case object (Name = "Intake No"). ' +
            'Intake__c.Client__c (relationship Client__r) is the injured party Contact. ' +
            'Stage/status field is Status__c; lead score is Qualification_Score__c; AI summary is AI_Summary__c. ' +
            'Other Contact lookups on Intake__c: Referral__c and Questionnaire_Recipient__c. ' +
            'When asked about an intake and its client/party, traverse Client__r for Contact fields ' +
            '(e.g. Client__r.Name, Client__r.Phone, Client__r.Email, Client__r.MailingState).\n' +
            'The current user is ' + UserInfo.getName() + ' (Id: ' + UserInfo.getUserId() + '). ' +
            'For "my ..." questions filter by the relevant owner/user field = that Id (e.g. OwnerId).\n' +
            'Objection playbook: when the user asks how to handle a client objection, what to say to a client, ' +
            'or for a recommended response/script (e.g. "how do I handle the fee objection", "client wants to think about it"), ' +
            'call faq_lookup and base your answer on the firm\'s APPROVED entries it returns. Never invent a script; ' +
            'if no approved entry matches, say the playbook has no approved answer for that yet. ' +
            'Each entry includes how often it was seen and its handled-success rate — prefer higher success-rate responses.\n' +
            'Executive intelligence: for forecasting questions ("how many will we sign", "pipeline outlook", ' +
            '"are we on track") call conversion_forecast. For marketing-source questions ("which source is best", ' +
            '"cost per signed case", "where to move budget") call source_quality. Quote only the numbers these tools ' +
            'return, and note each forecast\'s confidence band.\n' +
            'Do not query or display restricted personal fields (SSN, date of birth, age) — if asked, ' +
            'explain you cannot share those.\n' +
            'Refuse only clearly non-Salesforce requests (general knowledge, coding, math, chit-chat) ' +
            'with one sentence: "I can only help with this firm\'s Salesforce data." ' +
            'Format answers with simple HTML (bold, <ul> lists, small <table>s) since the UI renders rich text.';

        String ctx = buildCaseContext(recordId);
        if (String.isNotBlank(ctx)) s += '\n\n' + ctx;
        if (String.isNotBlank(conversationHistory)) s += '\n\nConversation so far:\n' + conversationHistory;
        return s;
    }

    private static String buildCaseContext(String recordId) {
        if (String.isBlank(recordId)) return '';
        List<Intake__c> recs = [
            SELECT Client__r.Name, Incident_Type__c, Status__c, AI_Summary__c
            FROM Intake__c WHERE Id = :recordId WITH USER_MODE LIMIT 1
        ];
        if (recs.isEmpty()) return '';
        Intake__c i = recs[0];
        return 'The user is currently viewing this Intake (Id: ' + recordId + '):\n'
            + '- Name: ' + (i.Client__r != null ? i.Client__r.Name : '') + '\n'
            + '- Accident Type: ' + i.Incident_Type__c + '\n'
            + '- Status: ' + i.Status__c + '\n'
            + '- AI Summary: ' + i.AI_Summary__c;
    }

    private static Map<String, Object> msg(String role, String text) {
        return new Map<String, Object>{ 'role' => role, 'content' => text };
    }

    private static String extractText(List<Object> content) {
        if (content != null) {
            for (Object blkObj : content) {
                Map<String, Object> blk = (Map<String, Object>) blkObj;
                if (blk.get('type') == 'text') return (String) blk.get('text');
            }
        }
        return 'No response generated.';
    }
}