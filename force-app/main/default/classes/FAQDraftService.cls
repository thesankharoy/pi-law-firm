/**
 * Drafts a best-practice response for a cluster, grounded in the firm's OWN winning
 * (signed-call) responses for that objection/question. This is text generation — the output
 * is always a DRAFT a human must approve, so no number guardrail applies here.
 */
public with sharing class FAQDraftService {

    private static final Integer MAX_TOKENS = 600;

    private static final String SYSTEM_PROMPT =
        'You write a concise best-practice response script for a personal-injury law-firm intake ' +
        'specialist, grounded ONLY in the firm\'s own winning examples provided. Keep it practical, ' +
        'compliant, and under 150 words. Do not promise outcomes or specific dollar amounts.';

    public static String draftResponse(String title, List<String> winningResponses, List<String> examples) {
        String prompt = 'Topic: ' + title + '\n\n';
        if (winningResponses != null && !winningResponses.isEmpty()) {
            prompt += 'Responses that led to signed retainers (learn from these):\n';
            for (String r : winningResponses) {
                if (String.isNotBlank(r)) prompt += '- ' + r + '\n';
            }
        }
        if (examples != null && !examples.isEmpty()) {
            prompt += '\nHow clients phrased it:\n';
            for (String x : examples) {
                if (String.isNotBlank(x)) prompt += '- ' + x + '\n';
            }
        }
        prompt += '\nWrite the recommended response script.';

        AnthropicCalloutService.Result ai = AnthropicCalloutService.complete(
            WinLossConfig.model(), MAX_TOKENS, SYSTEM_PROMPT, prompt);
        return ai.text == null ? null : ai.text.trim();
    }
}