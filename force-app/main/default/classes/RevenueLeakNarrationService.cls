/**
 * Turns a set of deterministically-detected, deterministically-valued leaks into a
 * ranked, plain-language digest.
 *
 * Claude is given ONLY the figures we computed plus non-dollar firm context, and is
 * asked to rank and explain — never to compute. The guardrail then verifies that every
 * dollar figure in Claude's reply is one we sent; if any figure is invented or altered,
 * the AI narrative is discarded and the deterministic template is used instead.
 */
public with sharing class RevenueLeakNarrationService {

    private static final Integer MAX_TOKENS = 1024;

    private static final String SYSTEM_PROMPT =
        'You are a revenue-intelligence assistant for a personal-injury law firm. ' +
        'You receive a list of detected revenue leaks with pre-computed figures and rank ' +
        'and explain them for the firm owner. STRICT RULE: you may only reference the exact ' +
        'dollar figures provided to you. Never compute, sum, round, estimate, or invent any ' +
        'dollar amount. Always write dollar figures with a leading "$". Be concise and ' +
        'action-oriented.';

    public class NarrationResult {
        public List<Revenue_Leak__c> leaks;
        public String narrative;
        public String source;       // 'AI' | 'Template'
        public String model;
        public Integer inputTokens;
        public Integer outputTokens;
        public Decimal totalValue;
    }

    /** Builds the digest for the given Open leaks (already queried with Intake__r fields). */
    public static NarrationResult narrate(List<Revenue_Leak__c> leaks) {
        NarrationResult out = new NarrationResult();
        out.leaks = leaks == null ? new List<Revenue_Leak__c>() : leaks;
        out.source = 'Template';

        Decimal total = 0;
        for (Revenue_Leak__c l : out.leaks) {
            total += (l.Estimated_Value__c == null ? 0 : l.Estimated_Value__c);
        }
        out.totalValue = total;

        if (out.leaks.isEmpty()) {
            out.narrative = '';
            return out;
        }

        // The only dollar figures Claude is allowed to echo: each estimate + the grand total.
        Set<Long> allowed = new Set<Long>();
        for (Revenue_Leak__c l : out.leaks) {
            allowed.add(toDollars(l.Estimated_Value__c));
        }
        allowed.add(toDollars(total));

        // Deterministic template is both the default and the guardrail fallback.
        out.narrative = templateNarrative(out.leaks, total);

        try {
            AnthropicCalloutService.Result r = AnthropicCalloutService.complete(
                RevenueLeakConfig.model(), MAX_TOKENS, SYSTEM_PROMPT, buildPrompt(out.leaks, total));

            if (guardrailPasses(r.text, allowed)) {
                out.narrative = r.text.trim();
                out.source = 'AI';
                out.model = r.model;
                out.inputTokens = r.inputTokens;
                out.outputTokens = r.outputTokens;
            }
            // else: guardrail tripped — keep the deterministic template, source stays 'Template'.
        } catch (Exception e) {
            // Any callout/parse failure: keep the deterministic template.
        }
        return out;
    }

    // ── Guardrail ────────────────────────────────────────────────────
    /** True when every $-figure in the text is one we provided. */
    @TestVisible
    private static Boolean guardrailPasses(String text, Set<Long> allowed) {
        if (String.isBlank(text)) return false;
        Matcher m = Pattern.compile('\\$\\s?[0-9][0-9,]*(\\.[0-9]+)?').matcher(text);
        while (m.find()) {
            if (!allowed.contains(toDollars(parseMoney(m.group())))) {
                return false;
            }
        }
        return true;
    }

    private static Decimal parseMoney(String token) {
        String cleaned = token.replaceAll('[^0-9.]', '');
        return String.isBlank(cleaned) ? 0 : Decimal.valueOf(cleaned);
    }

    private static Long toDollars(Decimal d) {
        return d == null ? 0L : d.setScale(0, System.RoundingMode.HALF_UP).longValue();
    }

    // ── Prompt construction ──────────────────────────────────────────
    private static String buildPrompt(List<Revenue_Leak__c> leaks, Decimal total) {
        // Non-dollar firm context: historical retainer sign-through rate.
        Integer signed = [SELECT COUNT() FROM Intake__c WHERE Status__c = 'Retainer Agreement Signed'];
        Integer sent = [SELECT COUNT() FROM Intake__c WHERE Status__c = 'Retainer Agreement Sent'];
        Integer denom = signed + sent;
        Integer signRatePct = denom == 0 ? 0 : (signed * 100) / denom;

        String s = 'Firm context: historical retainer sign-through rate is approximately '
            + signRatePct + '%.\n\n'
            + 'Open unsigned-retainer leaks (figures are final — quote them exactly):\n';
        Integer n = 1;
        for (Revenue_Leak__c l : leaks) {
            String client = (l.Intake__r != null && l.Intake__r.Client__r != null
                && l.Intake__r.Client__r.Name != null) ? l.Intake__r.Client__r.Name : 'Unknown client';
            String matter = (l.Intake__r != null && String.isNotBlank(l.Intake__r.Incident_Type__c))
                ? l.Intake__r.Incident_Type__c : 'Unspecified';
            String channel = (l.Intake__r != null && String.isNotBlank(l.Intake__r.Lead_Source_Channel__c))
                ? l.Intake__r.Lead_Source_Channel__c : 'Unknown';
            s += n + '. Intake ' + (l.Intake__r != null ? l.Intake__r.Name : l.Intake__c)
                + ' — client ' + client + ', matter type ' + matter + ', lead source ' + channel
                + ', ' + intval(l.Days_Overdue__c) + ' business day(s) overdue, '
                + 'sign probability ' + intval(l.Sign_Probability__c) + '%, '
                + 'risk-adjusted value $' + money(l.Estimated_Value__c) + '.\n';
            n++;
        }
        s += '\nTotal risk-adjusted value at stake: $' + money(total) + '.\n\n'
            + 'Rank these leaks from most to least urgent and explain, in 1-2 sentences each, '
            + 'why the owner should act. Then give one short overall recommendation. '
            + 'Remember: only use the exact dollar figures above.';
        return s;
    }

    // ── Deterministic template (fallback + default) ──────────────────
    private static String templateNarrative(List<Revenue_Leak__c> leaks, Decimal total) {
        String s = leaks.size() + ' unsigned retainer(s) are past SLA, $' + money(total)
            + ' in risk-adjusted value at stake. Ranked by value:\n';
        Integer n = 1;
        for (Revenue_Leak__c l : leaks) {
            String client = (l.Intake__r != null && l.Intake__r.Client__r != null
                && l.Intake__r.Client__r.Name != null) ? l.Intake__r.Client__r.Name : 'Unknown client';
            s += n + '. Intake ' + (l.Intake__r != null ? l.Intake__r.Name : l.Intake__c)
                + ' (' + client + ') — $' + money(l.Estimated_Value__c) + ' at risk, '
                + intval(l.Days_Overdue__c) + ' day(s) overdue [' + l.Severity__c + '].\n';
            n++;
        }
        s += 'Follow up on the highest-value retainers first.';
        return s;
    }

    private static String money(Decimal d) {
        return (d == null ? 0 : d).setScale(0, System.RoundingMode.HALF_UP).format();
    }
    private static Integer intval(Decimal d) {
        return d == null ? 0 : d.intValue();
    }
}