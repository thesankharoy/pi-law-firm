/**
 * Classifies one lost intake's transcript into the closed taxonomy and mines objections.
 * Builds in-memory records only (the batch does all callouts first, then DML).
 *
 * Guardrail 1: off-taxonomy reason/objection snaps to a safe default (in WinLossTaxonomy).
 * Guardrail 2: the evidence quote must be a real substring of the transcript and confidence
 *              must meet the threshold, else the record is flagged Needs_Review__c.
 */
public with sharing class LossExtractionService {

    private static final Integer MAX_TOKENS = 1024;

    private static final String SYSTEM_PROMPT =
        'You are an intake-quality analyst for a personal-injury law firm. You read the call ' +
        'transcript of a prospect who did NOT sign and determine why. You must choose values only ' +
        'from the closed lists given to you, copy the evidence quote VERBATIM from the transcript, ' +
        'and never invent facts. Return ONLY a JSON object, no prose, no markdown.';

    public class ExtractionResult {
        public Loss_Analysis__c analysis;
        public List<Objection__c> objections = new List<Objection__c>();
    }

    public static ExtractionResult extract(Intake__c i) {
        String transcript = transcriptText(i);

        Loss_Analysis__c a = new Loss_Analysis__c();
        a.Intake__c = i.Id;
        a.Incident_Type__c = i.Incident_Type__c;
        a.Source__c = (String) safeGet(i, 'Source__c');
        if (i.OwnerId != null && i.OwnerId.getSObjectType() == Schema.User.SObjectType) {
            a.Specialist__c = i.OwnerId;
        }
        a.Model__c = WinLossConfig.model();

        ExtractionResult res = new ExtractionResult();
        res.analysis = a;

        if (String.isBlank(transcript)) {
            a.Primary_Reason__c = WinLossTaxonomy.UNCLASSIFIED;
            a.Fault_Category__c = WinLossTaxonomy.FAULT_UNKNOWN;
            a.Needs_Review__c = true;
            a.Summary__c = 'No transcript or description available to classify.';
            return res;
        }

        AnthropicCalloutService.Result r;
        try {
            r = AnthropicCalloutService.complete(
                WinLossConfig.model(), MAX_TOKENS, SYSTEM_PROMPT, buildPrompt(i, transcript));
        } catch (Exception e) {
            a.Primary_Reason__c = WinLossTaxonomy.UNCLASSIFIED;
            a.Fault_Category__c = WinLossTaxonomy.FAULT_UNKNOWN;
            a.Needs_Review__c = true;
            a.Summary__c = 'Classification callout failed: ' + e.getMessage();
            return res;
        }

        Map<String, Object> parsed = parseJson(r.text);

        String reason = WinLossTaxonomy.safeReason((String) parsed.get('primaryReason'));
        a.Primary_Reason__c = reason;
        a.Fault_Category__c = WinLossTaxonomy.faultFor(reason);
        a.Summary__c = trim(asString(parsed.get('summary')), 4000);

        Decimal conf = toDecimal(parsed.get('confidence'));
        a.Confidence__c = conf;
        String quote = asString(parsed.get('evidenceQuote'));
        a.Evidence_Quote__c = trim(quote, 4000);

        Boolean quoteOk = String.isNotBlank(quote) && containsNormalized(transcript, quote);
        Boolean confOk = conf != null && conf >= WinLossConfig.confidenceThreshold();
        a.Needs_Review__c = !(quoteOk && confOk) || reason == WinLossTaxonomy.UNCLASSIFIED;

        Object objs = parsed.get('objections');
        if (objs instanceof List<Object>) {
            for (Object o : (List<Object>) objs) {
                if (!(o instanceof Map<String, Object>)) continue;
                Map<String, Object> m = (Map<String, Object>) o;
                Objection__c ob = new Objection__c();
                ob.Intake__c = i.Id;
                ob.Objection_Type__c = WinLossTaxonomy.safeObjection((String) m.get('type'));
                ob.Quote__c = trim(asString(m.get('quote')), 4000);
                res.objections.add(ob);
            }
        }
        return res;
    }

    // ── prompt ───────────────────────────────────────────────────────
    private static String buildPrompt(Intake__c i, String transcript) {
        String tdReason = (String) safeGet(i, 'Turn_Down_Reason__c');
        String tdDetails = (String) safeGet(i, 'Turn_Down_Details__c');
        return 'Closed reason list (pick exactly one for primaryReason): '
            + WinLossTaxonomy.reasonList() + '\n'
            + 'Closed objection list (pick from these for each objection type): '
            + WinLossTaxonomy.objectionList() + '\n\n'
            + (String.isNotBlank(tdReason) ? ('Intake-recorded turn-down reason: ' + tdReason + '\n') : '')
            + (String.isNotBlank(tdDetails) ? ('Turn-down details: ' + tdDetails + '\n') : '')
            + '\nTranscript:\n"""\n' + transcript + '\n"""\n\n'
            + 'Return ONLY this JSON object:\n'
            + '{\n'
            + '  "primaryReason": "one value from the reason list",\n'
            + '  "confidence": 0.0,\n'
            + '  "evidenceQuote": "a short verbatim quote copied exactly from the transcript",\n'
            + '  "summary": "one plain-language sentence",\n'
            + '  "objections": [{"type": "one value from the objection list", "quote": "verbatim quote"}]\n'
            + '}\n'
            + 'Use an empty array if there were no objections. confidence is 0.0-1.0.';
    }

    // ── helpers ──────────────────────────────────────────────────────
    private static String transcriptText(Intake__c i) {
        String t = (String) safeGet(i, 'Transcript__c');
        if (String.isNotBlank(t)) return t;
        return (String) safeGet(i, 'Incident_Description__c');
    }

    private static Object safeGet(SObject s, String field) {
        try {
            return s.get(field);
        } catch (Exception e) {
            return null;
        }
    }

    /** Whitespace- and case-insensitive substring check for the evidence guardrail. */
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

    private static String asString(Object o) {
        return o == null ? null : String.valueOf(o);
    }
    private static String trim(String s, Integer len) {
        if (s == null) return null;
        return s.length() > len ? s.substring(0, len) : s;
    }
    private static Decimal toDecimal(Object o) {
        if (o == null) return null;
        try {
            return Decimal.valueOf(String.valueOf(o));
        } catch (Exception e) {
            return null;
        }
    }
}