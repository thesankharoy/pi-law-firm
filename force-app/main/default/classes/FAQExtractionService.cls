/**
 * Mines one call transcript (won OR lost) for the questions and objections the client raised
 * and the response the specialist gave. Builds in-memory FAQ_Candidate__c rows (the batch does
 * all callouts first, then DML).
 *
 * Reuses the #73 objection taxonomy (WinLossTaxonomy) and the #69 evidence guardrail:
 * each verbatim text must be a real substring of the transcript, else Needs_Review__c.
 */
public with sharing class FAQExtractionService {

    private static final Integer MAX_TOKENS = 1500;

    private static final String SYSTEM_PROMPT =
        'You analyze a personal-injury intake call transcript and extract every distinct ' +
        'QUESTION the client asked and every OBJECTION the client raised, along with the ' +
        'response the specialist gave to each. Copy text VERBATIM from the transcript. Never ' +
        'invent. Return ONLY a JSON object.';

    public static List<FAQ_Candidate__c> extract(Intake__c i, Boolean signed) {
        List<FAQ_Candidate__c> out = new List<FAQ_Candidate__c>();
        String transcript = transcriptText(i);
        if (String.isBlank(transcript)) return out;

        AnthropicCalloutService.Result ai;
        try {
            ai = AnthropicCalloutService.complete(
                WinLossConfig.model(), MAX_TOKENS, SYSTEM_PROMPT, buildPrompt(transcript));
        } catch (Exception e) {
            return out; // a failed call simply yields no candidates this run
        }

        Map<String, Object> parsed = parseJson(ai.text);
        Object items = parsed.get('items');
        if (!(items instanceof List<Object>)) return out;

        for (Object o : (List<Object>) items) {
            if (!(o instanceof Map<String, Object>)) continue;
            Map<String, Object> m = (Map<String, Object>) o;

            String text = asString(m.get('text'));
            if (String.isBlank(text)) continue;

            Boolean isObjection = 'Objection'.equalsIgnoreCase(asString(m.get('kind')));
            FAQ_Candidate__c c = new FAQ_Candidate__c();
            c.Intake__c = i.Id;
            c.Kind__c = isObjection ? 'Objection' : 'Question';
            c.Raw_Text__c = trim(text, 4000);
            c.Response_Given__c = trim(asString(m.get('responseGiven')), 4000);
            c.Led_To_Signing__c = signed;
            c.Confidence__c = 0.8;
            c.Needs_Review__c = !containsNormalized(transcript, text);

            if (isObjection) {
                String ot = WinLossTaxonomy.safeObjection(asString(m.get('objectionType')));
                c.Objection_Type__c = ot;
                c.Cluster_Key__c = 'OBJ:' + ot;
            } else {
                c.Cluster_Key__c = 'Q:' + normalizeCategory(asString(m.get('category')));
            }
            out.add(c);
        }
        return out;
    }

    // ── prompt ───────────────────────────────────────────────────────
    private static String buildPrompt(String transcript) {
        return 'Objection types (use one of these when kind=Objection): '
            + WinLossTaxonomy.objectionList() + '\n\n'
            + 'Transcript:\n"""\n' + transcript + '\n"""\n\n'
            + 'Return ONLY this JSON object:\n'
            + '{"items":[{"kind":"Question|Objection","objectionType":"one objection type (only if kind=Objection)",'
            + '"category":"2-4 word topic (only if kind=Question)","text":"verbatim question/objection from the transcript",'
            + '"responseGiven":"verbatim specialist response, or empty"}]}\n'
            + 'Use an empty items array if there were none.';
    }

    // ── helpers ──────────────────────────────────────────────────────
    private static String normalizeCategory(String s) {
        if (String.isBlank(s)) return 'general';
        String n = s.toLowerCase().replaceAll('[^a-z0-9]+', '_').replaceAll('^_+|_+$', '');
        if (String.isBlank(n)) return 'general';
        return n.length() > 80 ? n.substring(0, 80) : n;
    }

    private static String transcriptText(Intake__c i) {
        String t = (String) safeGet(i, 'Transcript__c');
        if (String.isNotBlank(t)) return t;
        return (String) safeGet(i, 'Incident_Description__c');
    }
    private static Object safeGet(SObject s, String field) {
        try { return s.get(field); } catch (Exception e) { return null; }
    }

    @TestVisible
    private static Boolean containsNormalized(String haystack, String needle) {
        if (String.isBlank(haystack) || String.isBlank(needle)) return false;
        String h = haystack.toLowerCase().replaceAll('\\s+', ' ').trim();
        String n = needle.toLowerCase().replaceAll('\\s+', ' ').trim();
        return h.contains(n);
    }

    private static Map<String, Object> parseJson(String raw) {
        String s = raw == null ? '' : raw.trim();
        Integer a = s.indexOf('{');
        Integer b = s.lastIndexOf('}');
        if (a < 0 || b <= a) return new Map<String, Object>();
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(s.substring(a, b + 1));
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }
    private static String asString(Object o) { return o == null ? null : String.valueOf(o); }
    private static String trim(String s, Integer len) {
        if (s == null) return null;
        return s.length() > len ? s.substring(0, len) : s;
    }
}