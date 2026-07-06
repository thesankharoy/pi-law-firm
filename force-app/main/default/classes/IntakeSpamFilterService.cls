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

    static final String STATUS_SPAM = 'Spam';
    static final String STATUS_NEW  = 'New';

    // ── New_Intake RecordType Id cache ────────────────────────────────────────
    static Id newIntakeRtId;
    static Id getNewIntakeRtId() {
        if (newIntakeRtId == null) {
            newIntakeRtId = Schema.SObjectType.Intake__c
                .getRecordTypeInfosByDeveloperName()
                .get('New_Intake')
                .getRecordTypeId();
        }
        return newIntakeRtId;
    }

    // ── Result ────────────────────────────────────────────────────────────────
    public class FilterResult {
        public Boolean      isSpam;
        public Integer      score;
        public List<String> signals;
        public FilterResult() {
            signals = new List<String>();
            score   = 0;
            isSpam  = false;
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
                // FAIL OPEN — leave Status__c exactly as the lifecycle service
                // already set it (e.g. 'New') so the record flows through the
                // normal intake pipeline. Just log the failure for visibility.
                intake.Triage_Score__c   = null;
                intake.Triage_Signals__c = 'Layer-1 error (fail-open): ' + e.getMessage();
            }
        }
    }

    /** Called from after-insert trigger. Enqueues AI spam-check for anything Layer 1 didn't already flag. */
    public static void enqueueAITriage(List<Intake__c> intakes) {
        List<Id> toClassify = new List<Id>();
        for (Intake__c i : intakes) {
            if (i.Status__c != STATUS_SPAM) {
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
        Boolean injectionFound = false;
        for (String pat : INJECTION_PATTERNS) {
            if (description.contains(pat)) {
                r.signals.add('Injection/spam pattern detected: ' + pat);
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

        // ── Verdict — binary spam / not spam ────────────────────────────────
        r.score  = Math.min(r.score, 100);
        r.isSpam = r.score >= 65;

        return r;
    }

    // ── Apply verdict to Intake fields ────────────────────────────────────────
    static void applyVerdict(Intake__c intake, FilterResult r) {
        intake.Triage_Score__c   = r.score;
        intake.Triage_Signals__c = r.signals.isEmpty()
            ? 'No spam signals detected'
            : String.join(r.signals, '; ');

        if (r.isSpam) {
            intake.Status__c = STATUS_SPAM;
        } else {
            // A brand-new lead is never actually "handled" yet, even if an
            // assignment rule pointed it straight at a specialist and
            // IntakeLifecycleService.setInitialState() promoted it to
            // Active_Intake / Assigned. Every non-spam lead starts life as
            // New_Intake / New; it only becomes Active/Assigned later, when
            // a real user picks it up (see manageLifecycle's queue->user
            // transition). The AI check runs next as a second opinion and
            // can still flip this to Spam.
            intake.RecordTypeId = getNewIntakeRtId();
            intake.Status__c    = STATUS_NEW;
        }
    }

    static String safeStr(String s) {
        return s == null ? '' : s;
    }
}