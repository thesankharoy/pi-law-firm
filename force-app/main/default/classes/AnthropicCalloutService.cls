/**
 * Thin, reusable wrapper over the Anthropic Messages API.
 *
 * AI path: direct Anthropic API via Named Credential `Anthropic_Claude`, the same
 * credential already used by DocumentAnalysisService, IntakeCoPilotController and
 * SmsIntakeBotService. The `x-api-key` header is injected by the `Anthropic_Claude`
 * External Credential, so no API key is ever stored in source or in a custom setting.
 *
 * This is a deliberate exception to the Prompt-Builder-first rule (alongside document
 * analysis and the Live Call Co-Pilot): here Claude only ranks and explains figures we
 * computed deterministically — it is never asked to ground or generate facts.
 */
public with sharing class AnthropicCalloutService {
    public class CalloutException extends Exception {}

    @TestVisible
    private static final String NC = 'callout:Anthropic_Claude/v1/messages';
    private static final String ANTHROPIC_VERSION = '2023-06-01';
    public static final String DEFAULT_MODEL = 'claude-sonnet-4-6';

    /** Normalized result of one Messages call. */
    public class Result {
        public String text;
        public Integer inputTokens;
        public Integer outputTokens;
        public String model;
    }

    /**
     * Single-turn text completion. `userText` is sent as the user message content and
     * the concatenated text content blocks of the reply are returned.
     */
    public static Result complete(String model, Integer maxTokens, String systemPrompt, String userText) {
        Map<String, Object> userMsg = new Map<String, Object>{
            'role' => 'user',
            'content' => userText
        };
        Map<String, Object> body = new Map<String, Object>{
            'model' => String.isBlank(model) ? DEFAULT_MODEL : model,
            'max_tokens' => maxTokens,
            'messages' => new List<Object>{ userMsg }
        };
        if (String.isNotBlank(systemPrompt)) {
            body.put('system', systemPrompt);
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NC);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('anthropic-version', ANTHROPIC_VERSION);
        // x-api-key is injected by the `Anthropic_Claude` External Credential.
        req.setTimeout(120000);
        req.setBody(JSON.serialize(body));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException(
                'Anthropic API returned HTTP ' + res.getStatusCode() + ': ' + res.getBody());
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String text = '';
        Object content = parsed.get('content');
        if (content instanceof List<Object>) {
            for (Object o : (List<Object>) content) {
                Map<String, Object> blk = (Map<String, Object>) o;
                if (blk.get('type') == 'text') {
                    text += String.valueOf(blk.get('text'));
                }
            }
        }
        if (String.isBlank(text)) {
            throw new CalloutException('Anthropic API returned no text content.');
        }

        Result r = new Result();
        r.text = text;
        r.model = String.valueOf(parsed.get('model'));
        Map<String, Object> usage = (Map<String, Object>) parsed.get('usage');
        if (usage != null) {
            r.inputTokens = toInt(usage.get('input_tokens'));
            r.outputTokens = toInt(usage.get('output_tokens'));
        }
        return r;
    }

    private static Integer toInt(Object o) {
        return o == null ? null : Integer.valueOf(String.valueOf(o));
    }
}