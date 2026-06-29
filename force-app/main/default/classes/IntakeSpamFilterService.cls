/**
 * IntakeSpamFilterService
 *
 * Layer-1 deterministic spam/junk scoring.
 * Called synchronously from IntakeTrigger (before insert).
 *
 * NOTE: This version does NOT use Honeypot or Submit Duration —
 * those require web form access. Layer 1 is accordingly more
 * conservative (lower thresholds) and sends more to Layer 2 AI.
 *
 * Design principles:
 *  - FAIL OPEN: any unexpected exception → Needs Review, never auto-quarantine.
 *  - Never hard-delete: sets Lead_Triage_Status__c only.
 *  - Only obvious bots/spam quarantined here. Ambiguous → AI layer.
 *
 * Verdicts:
 *  'Pending AI Review'  – passed Layer 1; AI Queueable will classify
 *  'Spam'               – hard Layer-1 trip (injection/solicitation/test)
 *  'Needs Review'       – Layer 1 inconclusive OR any error
 */
public without sharing class IntakeSpamFilterService {

    // ── Disposable email domain list ──────────────────────────────────────────
    @TestVisible
    static final Set<String> DISPOSABLE_DOMAINS = new Set<String>{
        'mailinator.com', 'guerrillamail.com', 'tempmail.com', 'throwam.com',
        'yopmail.com', 'trashmail.com', 'sharklasers.com', 'guerrillamailblock.com',
        'grr.la', 'guerrillamail.info', 'spam4.me', 'dispostable.com',
        'maildrop.cc', 'mailnull.com', 'spamgourmet.com', 'trashmail.at',
        'discard.email', 'fakeinbox.com', 'tempinbox.com', 'filzmail.com',
        'spamhereplease.com', 'mailexpire.com', 'thanksnospam.com'
    };

    // ── URL / HTML injection patterns ─────────────────────────────────────────
    @TestVisible
    static final List<String> INJECTION_PATTERNS = new List<String>{
        '<script', 'href=', 'onclick=', '<a ',
        'http://', 'https://',
        'seo', 'backlink', 'rank your', 'page rank', 'search engine',
        'digital marketing', 'increase traffic', 'buy followers',
        'cryptocurrency', 'bitcoin', 'investment opportunity', 'make money fast'
    };

    // ── B2B / solicitation keywords ───────────────────────────────────────────
    @TestVisible
    static final List<String> SOLICITATION_KEYWORDS = new List<String>{
        'dear attorney', 'dear counselor', 'law firm marketing',
        'lead generation', 'we offer', 'our services', 'our company',
        'partnership opportunity', 'vendor', 'software solution',
        'crm solution', 'case management software', 'virtual assistant',
        'answering service', 'legal staffing'
    };

    // ── Gibberish / keyboard-mash patterns ───────────────────────────────────
    @TestVisible
    static final Pattern GIBBERISH_PATTERN = Pattern.compile(
        '([a-z])\\1{4,}|[qwerty]{6,}|[asdfgh]{6,}|[zxcvbn]{6,}|' +
        '^[^aeiou]{8,}$|aaaa|bbbb|cccc|dddd|eeee|ffff|gggg|hhhh|' +
        'jjjj|kkkk|llll|mmmm|nnnn|pppp|rrrr|ssss|tttt|uuuu|vvvv|' +
        'wwww|xxxx|yyyy|zzzz'
    );

    // ── Result ────────────────────────────────────────────────────────────────
    public enum Verdict { SPAM, NEEDS_REVIEW, PENDING_AI }

    public class FilterResult {
        public Verdict verdictValue;
        public Integer score;
        public List<String> signals;
        public FilterResult() {
            signals      = new List<String>();
            score        = 0;
            verdictValue = Verdict.PENDING_AI;
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  PUBLIC ENTRY POINTS
    // ══════════════════════════════════════════════════════════════════════════

    /** Called from before-insert trigger. Bulk-safe. */
    public static void evaluate(List<Intake__c> intakes) {
        for (Intake__c intake : intakes) {
            try {
                FilterResult result = runLayer1(intake);
                applyVerdict(intake, result);
            } catch (Exception e) {
                // FAIL OPEN
                intake.Lead_Triage_Status__c = 'Needs Review';
                intake.Triage_Score__c       = null;
                intake.Triage_Signals__c     = 'Layer-1 error: ' + e.getMessage();
            }
        }
    }

    /** Called from after-insert trigger. Enqueues AI triage for clean intakes. */
    public static void enqueueAITriage(List<Intake__c> intakes) {
        List<Id> toClassify = new List<Id>();
        for (Intake__c i : intakes) {
            if (i.Lead_Triage_Status__c == 'Pending AI Review') {
                toClassify.add(i.Id);
            }
        }
        if (!toClassify.isEmpty()) {
            System.enqueueJob(new IntakeAITriageQueueable(toClassify));
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  LAYER 1 — DETERMINISTIC CHECKS
    // ══════════════════════════════════════════════════════════════════════════
    @TestVisible
    static FilterResult runLayer1(Intake__c intake) {
        FilterResult r = new FilterResult();

        String description = safeStr(intake.Incident_Description__c).toLowerCase();
        String name         = (safeStr(intake.Submitter_First_Name__c) + ' ' +
                               safeStr(intake.Submitter_Last_Name__c)).trim().toLowerCase();
        String email        = safeStr(intake.Submitter_Email__c).toLowerCase().trim();
        String phone        = safeStr(intake.Submitter_Phone__c);
        String source       = safeStr(intake.Source__c).toLowerCase();

        // ── 1. Disposable email domain ────────────────────────────────────────
        if (String.isNotBlank(email) && email.contains('@')) {
            String domain = email.substringAfterLast('@');
            if (DISPOSABLE_DOMAINS.contains(domain)) {
                r.signals.add('Disposable email domain: ' + domain);
                r.score += 65;
            }
        }

        // ── 2. HTML injection in free-text fields ─────────────────────────────
        // Check for <script>, onclick=, <a href — hard signals
        String combined = description + ' ' + safeStr(intake.Incident_Description__c);
        Boolean injectionFound = false;
        for (String pat : INJECTION_PATTERNS) {
            if (combined.contains(pat)) {
                r.signals.add('Injection/spam pattern detected: ' + pat);
                // HTML tags = high confidence spam; marketing keywords = medium
                Integer pts = (pat.startsWith('<') || pat.contains('=')) ? 80 : 55;
                r.score += pts;
                injectionFound = true;
                break;
            }
        }

        // ── 3. B2B solicitation keywords ──────────────────────────────────────
        if (!injectionFound) {
            for (String kw : SOLICITATION_KEYWORDS) {
                if (description.contains(kw)) {
                    r.signals.add('Solicitation keyword: "' + kw + '"');
                    r.score += 55;
                    break;
                }
            }
        }

        // ── 4. Malformed / missing phone ──────────────────────────────────────
        if (String.isNotBlank(phone)) {
            String digits = phone.replaceAll('[^0-9]', '');
            if (digits.length() < 7) {
                r.signals.add('Phone has fewer than 7 digits: ' + phone);
                r.score += 30;
            }
        } else {
            // Blank phone — suspicious but not definitive; let AI decide
            r.signals.add('No phone number provided');
            r.score += 15;
        }

        // ── 5. Gibberish name ─────────────────────────────────────────────────
        if (String.isNotBlank(name) && name.length() > 3) {
            Matcher m = GIBBERISH_PATTERN.matcher(name.replaceAll('\\s', ''));
            if (m.find()) {
                r.signals.add('Gibberish name pattern: ' + name);
                r.score += 50;
            }
        }

        // ── 6. Gibberish / extremely short description ────────────────────────
        if (String.isBlank(description) || description.length() < 10) {
            r.signals.add('Description blank or under 10 chars');
            r.score += 20;
        } else {
            String descSnippet = description.replaceAll('\\s', '');
            String sample = descSnippet.substring(0, Math.min(descSnippet.length(), 30));
            if (String.isNotBlank(sample)) {
                Matcher m2 = GIBBERISH_PATTERN.matcher(sample);
                if (m2.find()) {
                    r.signals.add('Gibberish description pattern');
                    r.score += 40;
                }
            }
        }

        // ── 7. Explicit test / ignore markers ────────────────────────────────
        if (description.containsIgnoreCase('test submission') ||
            description.containsIgnoreCase('ignore this') ||
            source == 'test') {
            r.signals.add('Explicit test/ignore signal in submission');
            r.score += 80;
        }

        // ── Verdict ───────────────────────────────────────────────────────────
        // Thresholds are slightly lower than honeypot version because we have
        // fewer signals — be more conservative to avoid false positives.
        r.score = Math.min(r.score, 100);
        if (r.score >= 65) {
            r.verdictValue = Verdict.SPAM;
        } else if (r.score >= 30) {
            r.verdictValue = Verdict.NEEDS_REVIEW;
        } else {
            r.verdictValue = Verdict.PENDING_AI;
        }

        return r;
    }

    // ── Apply verdict to Intake fields ────────────────────────────────────────
    static void applyVerdict(Intake__c intake, FilterResult r) {
        intake.Triage_Score__c   = r.score;
        intake.Triage_Signals__c = r.signals.isEmpty()
            ? 'No Layer-1 signals detected'
            : String.join(r.signals, '; ');

        switch on r.verdictValue {
            when SPAM {
                intake.Lead_Triage_Status__c = 'Spam';
            }
            when NEEDS_REVIEW {
                intake.Lead_Triage_Status__c = 'Needs Review';
            }
            when PENDING_AI {
                intake.Lead_Triage_Status__c = 'Pending AI Review';
            }
        }
    }

    static String safeStr(String s) {
        return s == null ? '' : s;
    }
}