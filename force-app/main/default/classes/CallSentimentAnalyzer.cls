public with sharing class CallSentimentAnalyzer {

    private static final Integer MAX_TOKENS = 256;
    private static final Set<String> ALLOWED =
        new Set<String>{ 'Positive', 'Neutral', 'Negative', 'Mixed' };

    private static final String SYSTEM_PROMPT =
        'You analyze a single phone-call description/notes for a personal-injury law firm and ' +
        'judge the CLIENT\'s overall sentiment toward the firm. Be objective. Return ONLY a JSON ' +
        'object, no prose, no markdown.';

    public class Request {
        @InvocableVariable(label='Call Description' required=true)
        public String description;
    }
    public class Result {
        @InvocableVariable(label='Sentiment') public String sentiment;
        @InvocableVariable(label='Sentiment Score') public Decimal score;   // 0-100
        @InvocableVariable(label='Sentiment Summary') public String summary;
    }

    @InvocableMethod(label='Predict Call Sentiment' description='Sends a call description to Claude and returns the client sentiment.' category='AI')
    public static List<Result> predict(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) return results;
        for (Request req : requests) {
            results.add(analyzeOne(req == null ? null : req.description));
        }
        return results;
    }

    private static Result analyzeOne(String description) {
        Result r = new Result();
        r.sentiment = 'Neutral';
        r.score = 50;
        if (String.isBlank(description)) { r.summary = 'No call description to analyze.'; return r; }
        try {
            AnthropicCalloutService.Result ai = AnthropicCalloutService.complete(
                AnthropicCalloutService.DEFAULT_MODEL, MAX_TOKENS, SYSTEM_PROMPT, buildPrompt(description));
            Map<String, Object> parsed = parseJson(ai.text);
            String label = asString(parsed.get('sentiment'));
            r.sentiment = (label != null && ALLOWED.contains(label)) ? label : 'Neutral';
            Decimal sc = toDecimal(parsed.get('score'));
            if (sc != null) r.score = sc < 0 ? 0 : (sc > 100 ? 100 : sc);
            String sum = asString(parsed.get('summary'));
            r.summary = String.isBlank(sum) ? null : (sum.length() > 255 ? sum.substring(0, 255) : sum);
        } catch (Exception e) {
            r.sentiment = 'Neutral'; r.score = 50; r.summary = 'Sentiment analysis failed: ' + e.getMessage();
        }
        return r;
    }

    private static String buildPrompt(String description) {
        return 'Call description:\n"""\n' + description + '\n"""\n\n'
            + 'Return ONLY this JSON object:\n'
            + '{"sentiment":"Positive|Neutral|Negative|Mixed","score":0,"summary":"one short sentence"}\n'
            + 'sentiment is the CLIENT\'s feeling toward the firm. score is 0 (very negative) to '
            + '100 (very positive). Pick exactly one sentiment value from the four listed.';
    }

    private static Map<String, Object> parseJson(String raw) {
        String s = raw == null ? '' : raw.trim();
        Integer a = s.indexOf('{'); Integer b = s.lastIndexOf('}');
        if (a < 0 || b <= a) return new Map<String, Object>();
        try { return (Map<String, Object>) JSON.deserializeUntyped(s.substring(a, b + 1)); }
        catch (Exception e) { return new Map<String, Object>(); }
    }
    private static String asString(Object o) { return o == null ? null : String.valueOf(o); }
    private static Decimal toDecimal(Object o) {
        if (o == null) return null;
        try { return Decimal.valueOf(String.valueOf(o)); } catch (Exception e) { return null; }
    }
}