/**
 * Turns the deterministic aggregates into an executive digest. Claude ranks and explains;
 * Guardrail 3 verifies every percentage and every integer >= 10 in the reply is a figure we
 * computed, else the deterministic template is used instead.
 */
public with sharing class LossNarrationService {

    private static final Integer MAX_TOKENS = 1024;

    private static final String SYSTEM_PROMPT =
        'You are a revenue-intelligence assistant for a personal-injury law firm. You receive ' +
        'pre-computed win/loss figures and write a short executive digest for the firm owner. ' +
        'STRICT RULE: only use the exact numbers provided. Never compute, sum, round, estimate, ' +
        'or invent any number or percentage. Lead with how many losses were Process (fixable). ' +
        'Be concise and action-oriented.';

    public class NarrationResult {
        public String narrative;
        public String source;       // 'AI' | 'Template'
        public String model;
        public Integer inputTokens;
        public Integer outputTokens;
        public Integer total;
        public Integer processCount;
    }

    public static NarrationResult narrate(LossAggregationService.Aggregates a) {
        NarrationResult out = new NarrationResult();
        out.source = 'Template';
        out.total = a.total;
        out.processCount = a.processCount;
        out.narrative = template(a);

        if (a.total == 0) return out;

        Set<Integer> allowed = allowedNumbers(a);
        try {
            AnthropicCalloutService.Result r = AnthropicCalloutService.complete(
                WinLossConfig.model(), MAX_TOKENS, SYSTEM_PROMPT, buildPrompt(a));
            if (guardrailPasses(r.text, allowed)) {
                out.narrative = r.text.trim();
                out.source = 'AI';
                out.model = r.model;
                out.inputTokens = r.inputTokens;
                out.outputTokens = r.outputTokens;
            }
        } catch (Exception e) {
            // keep deterministic template
        }
        return out;
    }

    // ── Guardrail 3 ──────────────────────────────────────────────────
    @TestVisible
    private static Boolean guardrailPasses(String text, Set<Integer> allowed) {
        if (String.isBlank(text)) return false;
        // Every percentage must be allowed.
        Matcher pm = Pattern.compile('([0-9]+)\\s*%').matcher(text);
        while (pm.find()) {
            if (!allowed.contains(Integer.valueOf(pm.group(1)))) return false;
        }
        // Every integer >= 10 must be allowed.
        Matcher im = Pattern.compile('\\b([0-9]{2,})\\b').matcher(text);
        while (im.find()) {
            Integer v = Integer.valueOf(im.group(1));
            if (v >= 10 && !allowed.contains(v)) return false;
        }
        return true;
    }

    private static Set<Integer> allowedNumbers(LossAggregationService.Aggregates a) {
        Set<Integer> s = new Set<Integer>();
        s.add(a.total);
        s.add(a.processCount);
        s.add(a.processPct);
        s.add(a.lookbackDays);
        s.add(a.topReasonCount);
        s.add(a.topObjectionCount);
        s.addAll(a.byFault.values());
        s.addAll(a.byReason.values());
        s.addAll(a.byObjection.values());
        if (a.total > 0) {
            for (Integer c : a.byFault.values()) s.add((c * 100) / a.total);
            for (Integer c : a.byReason.values()) s.add((c * 100) / a.total);
        }
        return s;
    }

    // ── prompt + template ────────────────────────────────────────────
    private static String buildPrompt(LossAggregationService.Aggregates a) {
        String s = 'Window: last ' + a.lookbackDays + ' days.\n'
            + 'Total losses analyzed: ' + a.total + '.\n'
            + 'By fault category (count):\n';
        for (String k : a.byFault.keySet()) s += '  - ' + k + ': ' + a.byFault.get(k) + '\n';
        s += 'Process (fixable) losses: ' + a.processCount + ' (' + a.processPct + '%).\n';
        s += 'Top reasons (count):\n';
        for (String k : a.byReason.keySet()) s += '  - ' + k + ': ' + a.byReason.get(k) + '\n';
        s += 'Top objections (count):\n';
        for (String k : a.byObjection.keySet()) s += '  - ' + k + ': ' + a.byObjection.get(k) + '\n';
        s += '\nWrite a short digest: lead with the Process (fixable) share, name the single biggest '
            + 'fixable driver and the top objection, and give one concrete recommendation. '
            + 'Only use the exact numbers above.';
        return s;
    }

    private static String template(LossAggregationService.Aggregates a) {
        if (a.total == 0) {
            return 'No losses recorded in the last ' + a.lookbackDays + ' days.';
        }
        String s = 'Over the last ' + a.lookbackDays + ' days, ' + a.total + ' losses were analyzed. '
            + a.processCount + ' (' + a.processPct + '%) were Process — our own fixable issues.';
        if (String.isNotBlank(a.topReason)) {
            s += ' Biggest single reason: ' + a.topReason.replace('_', ' ')
                + ' (' + a.topReasonCount + ').';
        }
        if (String.isNotBlank(a.topObjection)) {
            s += ' Top objection: ' + a.topObjection.replace('_', ' ')
                + ' (' + a.topObjectionCount + ').';
        }
        s += ' Focus on the Process losses first — those are recoverable.';
        return s;
    }
}