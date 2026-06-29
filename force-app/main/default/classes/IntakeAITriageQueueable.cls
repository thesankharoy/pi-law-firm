/**
 * IntakeAITriageQueueable
 *
 * Layer-2 AI spam/junk classification using Claude.
 * Called async from after-insert trigger via IntakeSpamFilterService.enqueueAITriage().
 *
 * Named Credential: Anthropic_Claude  (https://api.anthropic.com)
 * Model: claude-opus-4-8 — highest accuracy for classification (per user config).
 *
 * FAIL-OPEN GUARANTEE:
 *   Any exception → Lead_Triage_Status__c = 'Needs Review'. Never auto-spammed on error.
 *
 * Verdicts (enum-constrained via tool use):
 *   Real          – genuine PI prospect
 *   Spam          – bot / injection / solicitation / test
 *   Junk          – real human, wrong fit (wrong area, no injury, expired SoL, prank)
 *   Needs_Review  – ambiguous; human should decide
 *
 * Batch size: 5 per job (well under 2-min Queueable limit). Chains for remainder.
 */
public without sharing class IntakeAITriageQueueable implements Queueable, Database.AllowsCallouts {

    static final Integer BATCH_SIZE  = 5;
    static final String  MODEL       = 'claude-opus-4-8';
    static final String  NC_ENDPOINT = 'callout:Anthropic_Claude/v1/messages';
    static final String  TOOL_NAME   = 'classify_intake';

    static final Set<String> VALID_VERDICTS = new Set<String>{
        'Real', 'Spam', 'Junk', 'Needs_Review'
    };

    private List<Id> intakeIds;

    public IntakeAITriageQueueable(List<Id> intakeIds) {
        this.intakeIds = intakeIds;
    }

    public void execute(QueueableContext ctx) {
        List<Id> batch     = new List<Id>();
        List<Id> remaining = new List<Id>();

        for (Integer i = 0; i < intakeIds.size(); i++) {
            if (i < BATCH_SIZE) {
                batch.add(intakeIds[i]);
            } else {
                remaining.add(intakeIds[i]);
            }
        }

        processBatch(batch);

        if (!remaining.isEmpty()) {
            System.enqueueJob(new IntakeAITriageQueueable(remaining));
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  BATCH PROCESSOR
    // ══════════════════════════════════════════════════════════════════════════
    void processBatch(List<Id> ids) {
        List<Intake__c> intakes = [
            SELECT Id, Name,
                   Submitter_First_Name__c, Submitter_Last_Name__c,
                   Submitter_Email__c, Submitter_Phone__c,
                   Incident_Type__c, Incident_Date__c,
                   Incident_Description__c, Injury_Severity__c,
                   Medical_Treatment_Status__c, Police_Called__c,
                   Insurance_Available__c, Liability_Clarity__c,
                   Source__c, Triage_Score__c, Triage_Signals__c
            FROM   Intake__c
            WHERE  Id IN :ids
        ];

        List<Intake__c> toUpdate = new List<Intake__c>();

        for (Intake__c intake : intakes) {
            try {
                AITriageResult result = classify(intake);
                Intake__c upd = new Intake__c(Id = intake.Id);
                upd.Lead_Triage_Status__c   = mapVerdict(result.verdict);
                upd.AI_Triage_Verdict__c    = result.verdict;
                upd.AI_Triage_Confidence__c = result.confidence;
                upd.AI_Triage_Reason__c     = result.reason;
                upd.AI_Triage_Timestamp__c  = System.now();
                toUpdate.add(upd);
            } catch (Exception e) {
                Intake__c upd = new Intake__c(Id = intake.Id);
                upd.Lead_Triage_Status__c  = 'Needs Review';
                upd.AI_Triage_Verdict__c   = 'Needs_Review';
                upd.AI_Triage_Reason__c    = 'AI triage error (fail-open): ' + e.getMessage();
                upd.AI_Triage_Timestamp__c = System.now();
                toUpdate.add(upd);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  CLAUDE API CALL — tool-use for structured enum output
    // ══════════════════════════════════════════════════════════════════════════
    @TestVisible
    AITriageResult classify(Intake__c intake) {
        String prompt      = buildPrompt(intake);
        String requestBody = buildRequestBody(prompt);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NC_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('anthropic-version', '2023-06-01');
        req.setTimeout(30000);
        req.setBody(requestBody);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() != 200) {
            throw new IntakeAITriageException(
                'Claude API returned ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        return parseResponse(res.getBody());
    }

    // ── Prompt ────────────────────────────────────────────────────────────────
    @TestVisible
    static String buildPrompt(Intake__c intake) {
        List<String> parts = new List<String>();
        parts.add('Name: '             + safeVal(intake.Submitter_First_Name__c) + ' ' + safeVal(intake.Submitter_Last_Name__c));
        parts.add('Email: '            + safeVal(intake.Submitter_Email__c));
        parts.add('Phone: '            + safeVal(intake.Submitter_Phone__c));
        parts.add('Incident type: '    + safeVal(intake.Incident_Type__c));
        parts.add('Incident date: '    + (intake.Incident_Date__c != null ? String.valueOf(intake.Incident_Date__c) : 'not provided'));
        parts.add('Injury severity: '  + safeVal(intake.Injury_Severity__c));
        parts.add('Medical treatment: '+ safeVal(intake.Medical_Treatment_Status__c));
        parts.add('Police called: '    + (intake.Police_Called__c ? 'Yes' : 'No'));
        parts.add('Insurance: '        + safeVal(intake.Insurance_Available__c));
        parts.add('Liability clarity: '+ safeVal(intake.Liability_Clarity__c));
        parts.add('Source: '           + safeVal(intake.Source__c));
        parts.add('Description:\n'     + safeVal(intake.Incident_Description__c));

        if (String.isNotBlank(intake.Triage_Signals__c)) {
            parts.add('\nLayer-1 deterministic signals already run: ' + intake.Triage_Signals__c);
            parts.add('Layer-1 score: ' + String.valueOf(intake.Triage_Score__c) + '/100');
        }

        return
            'You are a lead-triage assistant for a personal injury (PI) law firm. ' +
            'Your job is to protect intake specialists from wasting time on non-cases ' +
            'while ensuring ZERO real injured prospects are ever lost.\n\n' +
            'Classify this web lead as exactly one of: Real, Spam, Junk, or Needs_Review.\n\n' +
            'Definitions:\n' +
            '  Real         – a genuine injured person seeking PI legal representation. ' +
            'They describe a real incident, mention injury or damages, and have a plausible ' +
            'personal injury claim (auto accident, slip and fall, workers comp, medical ' +
            'malpractice, product liability, dog bite, wrongful death, etc.).\n' +
            '  Spam         – a bot, form scraper, link injector, B2B marketing solicitation, ' +
            'vendor pitch, test/dummy submission, or obvious fake. The description is absent, ' +
            'nonsensical, contains URLs/HTML, or is clearly commercial.\n' +
            '  Junk         – a real human who submitted but is not a viable PI case. ' +
            'Examples: wrong practice area (criminal, family, contract), no physical injury, ' +
            'statute of limitations clearly expired, prank, venting, or someone seeking ' +
            'free legal advice with no actionable claim.\n' +
            '  Needs_Review – genuinely ambiguous; a human specialist should decide. ' +
            'When in doubt, use this.\n\n' +
            'CRITICAL BIAS RULE: The cost of incorrectly flagging a real injured person ' +
            'as Spam or Junk is severe — a lost client and a lost contingency fee. ' +
            'Always err on the side of Real or Needs_Review when uncertain. ' +
            'Only mark Spam when you are highly confident (>85%) it is not a real person ' +
            'seeking injury representation. Only mark Junk when you are confident the person ' +
            'is real but the case is clearly not viable.\n\n' +
            'Lead data:\n' +
            String.join(parts, '\n') + '\n\n' +
            'Use the classify_intake tool to return your verdict, confidence (0.0–1.0), ' +
            'and a concise one-sentence reason suitable for display to an intake specialist.';
    }

    // ── Request body with tool use ────────────────────────────────────────────
    static String buildRequestBody(String prompt) {
        Map<String, Object> inputSchema = new Map<String, Object>{
            'type'       => 'object',
            'required'   => new List<String>{ 'verdict', 'confidence', 'reason' },
            'properties' => new Map<String, Object>{
                'verdict' => new Map<String, Object>{
                    'type'        => 'string',
                    'enum'        => new List<String>{ 'Real', 'Spam', 'Junk', 'Needs_Review' },
                    'description' => 'Classification verdict'
                },
                'confidence' => new Map<String, Object>{
                    'type'        => 'number',
                    'minimum'     => 0.0,
                    'maximum'     => 1.0,
                    'description' => 'Confidence in the verdict (0.0 = uncertain, 1.0 = certain)'
                },
                'reason' => new Map<String, Object>{
                    'type'        => 'string',
                    'description' => 'One-sentence explanation of the verdict for the intake specialist'
                }
            }
        };

        Map<String, Object> tool = new Map<String, Object>{
            'name'         => TOOL_NAME,
            'description'  => 'Classify a personal injury web lead.',
            'input_schema' => inputSchema
        };

        Map<String, Object> body = new Map<String, Object>{
            'model'       => MODEL,
            'max_tokens'  => 256,
            'tools'       => new List<Object>{ tool },
            'tool_choice' => new Map<String, Object>{ 'type' => 'tool', 'name' => TOOL_NAME },
            'messages'    => new List<Object>{
                new Map<String, Object>{ 'role' => 'user', 'content' => prompt }
            }
        };

        return JSON.serialize(body);
    }

    // ── Parse tool-use response ───────────────────────────────────────────────
    @TestVisible
    static AITriageResult parseResponse(String responseBody) {
        Map<String, Object> parsed  = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object>        content = (List<Object>) parsed.get('content');

        if (content == null || content.isEmpty()) {
            throw new IntakeAITriageException('Empty content array in Claude response');
        }

        for (Object block : content) {
            Map<String, Object> blk = (Map<String, Object>) block;
            if ('tool_use'.equals(blk.get('type')) && TOOL_NAME.equals(blk.get('name'))) {
                Map<String, Object> input = (Map<String, Object>) blk.get('input');

                String  verdict    = (String) input.get('verdict');
                Decimal confidence = input.get('confidence') instanceof Decimal
                    ? (Decimal) input.get('confidence')
                    : Decimal.valueOf(String.valueOf(input.get('confidence')));
                String  reason     = (String) input.get('reason');

                if (!VALID_VERDICTS.contains(verdict)) {
                    throw new IntakeAITriageException('Unexpected verdict: ' + verdict);
                }

                AITriageResult r = new AITriageResult();
                r.verdict    = verdict;
                r.confidence = confidence;
                r.reason     = reason;
                return r;
            }
        }

        throw new IntakeAITriageException('No tool_use block found in Claude response');
    }

    // ── Verdict → picklist value ──────────────────────────────────────────────
    static String mapVerdict(String verdict) {
        switch on verdict {
            when 'Real'         { return 'Real'; }
            when 'Spam'         { return 'Spam'; }
            when 'Junk'         { return 'Junk'; }
            when 'Needs_Review' { return 'Needs Review'; }
            when else           { return 'Needs Review'; }
        }
    }

    static String safeVal(String s) { return s == null ? 'not provided' : s; }

    // ── Inner types ───────────────────────────────────────────────────────────
    public class AITriageResult {
        public String  verdict;
        public Decimal confidence;
        public String  reason;
    }

    public class IntakeAITriageException extends Exception {}
}