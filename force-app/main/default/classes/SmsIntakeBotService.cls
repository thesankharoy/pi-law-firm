/**
 * Conversational SMS intake bot — Salesforce side.
 *
 * Layered on top of the TwilioSF managed package: inbound texts are logged as
 * TwilioSF__Message__c by the package (unchanged). This service watches new
 * INBOUND messages on the intake number, asks the copilot-service /sms brain for
 * the next empathetic reply, sends it back through TwilioSF (insert outbound
 * message), and — once the conversation is complete — creates the Contact +
 * Intake via PartyIntakeService.
 *
 * Routing: engages new leads; stands down automatically the moment a human
 * specialist replies from the inbox (an 'outbound-reply' message exists).
 */
public without sharing class SmsIntakeBotService {

    private static final String MODEL = 'claude-haiku-4-5-20251001';

    private static final String SYSTEM_PROMPT =
        'You are the first point of contact for people texting a personal-injury (PI) law firm. Many were just hurt and may be in pain, scared, or overwhelmed. Make them feel heard while gently gathering what the firm needs, and keep the conversation moving toward connecting them with a specialist.\n\n'
        + 'TONE & RULES:\n'
        + '- Lead with empathy, but keep it to ONE warm sentence, then move forward with the next needed question.\n'
        + '- NEVER open by asking for their name or personal details. That comes after they have shared what happened.\n'
        + '- Ask ONE gentle question at a time. Never interrogate or send a list of questions.\n'
        + '- Do NOT ask if they are okay more than once, and do not loop on comfort. Every message should make progress.\n'
        + '- Keep each message short and warm. This is SMS, not a form.\n'
        + '- Mirror their language; if they write in Spanish, reply in Spanish.\n\n'
        + 'WHAT TO GATHER, in order: 1) what happened (incident type), 2) whether they are hurt and getting any medical care, 3) roughly when it happened, 4) a short description in their words, 5) their name, asked gently so a specialist can follow up (for example: So our team can reach out and help you, may I ask your name?), 6) their email if it comes up naturally.\n\n'
        + 'PACING: once the client has described what happened and their injuries, your VERY NEXT message must gently ask for their name. Do not keep gathering details or reassuring once you have enough to proceed.\n\n'
        + 'COMPLETION: set complete=true as soon as you have the incident type, a description, and their name (email is optional). When complete, reply with one warm sentence that a specialist will reach out shortly, and ask no further questions. Always populate collected with everything known so far (null for unknown). Never fabricate.\n\n'
        + 'Respond ONLY by calling the emit_intake_turn tool.';

    private static final String TOOL_JSON =
        '{"name":"emit_intake_turn","description":"Return the next SMS reply plus everything gathered so far.",'
        + '"input_schema":{"type":"object","properties":{'
        + '"reply":{"type":"string","description":"The next SMS to send. Warm, brief, one gentle question at a time. Empty only when complete and no closing line is needed."},'
        + '"complete":{"type":"boolean","description":"True once we have at least the incident type, a description, and the client name."},'
        + '"collected":{"type":"object","properties":{'
        + '"firstName":{"type":["string","null"]},"lastName":{"type":["string","null"]},"email":{"type":["string","null"]},'
        + '"incidentType":{"type":["string","null"],"enum":["Car Accident","Truck Accident","Motorcycle Accident","Pedestrian Accident","Slip & Fall","Dog Bite","Medical Malpractice","Workplace Injury","Other",null]},"incidentDate":{"type":["string","null"]},'
        + '"injuries":{"type":["string","null"]},"treatment":{"type":["string","null"]},"description":{"type":["string","null"]}},'
        + '"required":["firstName","lastName","email","incidentType","incidentDate","injuries","treatment","description"]},'
        + '"leadFit":{"type":"string","enum":["Strong","Moderate","Weak","Red Flag"]}},'
        + '"required":["reply","complete","collected","leadFit"]}}';

    // Entry point from the trigger on TwilioSF__Message__c (after insert).
    public static void handleInbound(List<TwilioSF__Message__c> newMsgs) {
        SMS_Bot_Config__c cfg = SMS_Bot_Config__c.getOrgDefaults();
        String intakeNumber = (cfg != null) ? cfg.Intake_From_Number__c : null;

        List<TwilioSF__Message__c> inbound = new List<TwilioSF__Message__c>();
        Set<String> leadNumbers = new Set<String>();
        for (TwilioSF__Message__c m : newMsgs) {
            if (m.TwilioSF__Direction__c == 'inbound'
                && String.isNotBlank(m.TwilioSF__From_Number__c)
                && (String.isBlank(intakeNumber) || m.TwilioSF__To_Number__c == intakeNumber)) {
                inbound.add(m);
                leadNumbers.add(m.TwilioSF__From_Number__c);
            }
        }
        if (inbound.isEmpty()) return;

        // Handoff guard: if a human already replied (outbound-reply) in a thread,
        // the bot stays silent for that lead.
        Set<String> humanHandled = new Set<String>();
        for (TwilioSF__Message__c m : [
            SELECT TwilioSF__To_Number__c
            FROM TwilioSF__Message__c
            WHERE TwilioSF__Direction__c = 'outbound-reply'
              AND TwilioSF__To_Number__c IN :leadNumbers
        ]) {
            humanHandled.add(m.TwilioSF__To_Number__c);
        }

        for (TwilioSF__Message__c m : inbound) {
            if (humanHandled.contains(m.TwilioSF__From_Number__c)) continue;
            System.enqueueJob(new IntakeBotJob(m.Id));
        }
    }

    // One conversation turn: read thread -> ask Claude -> reply -> maybe finalize.
    public class IntakeBotJob implements Queueable, Database.AllowsCallouts {
        private final Id messageId;
        public IntakeBotJob(Id messageId) { this.messageId = messageId; }

        public void execute(QueueableContext ctx) {
            TwilioSF__Message__c msg = [
                SELECT TwilioSF__From_Number__c, TwilioSF__To_Number__c, TwilioSF__Contact__c
                FROM TwilioSF__Message__c WHERE Id = :messageId LIMIT 1
            ];
            String lead         = msg.TwilioSF__From_Number__c;
            String intakeNumber = msg.TwilioSF__To_Number__c;

            // Build the full thread for this lead, oldest first.
            List<Map<String, String>> history = new List<Map<String, String>>();
            for (TwilioSF__Message__c t : [
                SELECT TwilioSF__Direction__c, TwilioSF__Body__c
                FROM TwilioSF__Message__c
                WHERE (TwilioSF__From_Number__c = :lead OR TwilioSF__To_Number__c = :lead)
                ORDER BY TwilioSF__Date_Created__c ASC
            ]) {
                if (String.isBlank(t.TwilioSF__Body__c)) continue;
                history.add(new Map<String, String>{
                    'role' => (t.TwilioSF__Direction__c == 'inbound') ? 'client' : 'assistant',
                    'text' => t.TwilioSF__Body__c
                });
            }

            // Ask the copilot-service brain (callout BEFORE any DML in this txn).
            Map<String, Object> out = callBrain(history);
            if (out == null) return;

            String reply  = (String) out.get('reply');
            Boolean done  = out.get('complete') == true;
            Map<String, Object> collected = (Map<String, Object>) out.get('collected');

            // Reply via TwilioSF (lands in the inbox + delivers).
            if (String.isNotBlank(reply)) {
                insert new TwilioSF__Message__c(
                    TwilioSF__Direction__c   = 'outbound-api',
                    TwilioSF__From_Number__c = intakeNumber,
                    TwilioSF__To_Number__c   = lead,
                    TwilioSF__Body__c        = reply,
                    TwilioSF__Contact__c     = msg.TwilioSF__Contact__c
                );
            }

            if (done && collected != null) {
                finalizeIntake(lead, collected);
            }
        }

        // Calls the Anthropic Messages API directly (tool-use forces clean JSON).
        // Returns the emit_intake_turn input map: { reply, complete, collected, leadFit }.
        private Map<String, Object> callBrain(List<Map<String, String>> history) {
            // Map the thread to Anthropic messages (client -> user, bot -> assistant).
            List<Map<String, Object>> messages = new List<Map<String, Object>>();
            for (Map<String, String> m : history) {
                if (String.isBlank(m.get('text'))) continue;
                String role = (m.get('role') == 'assistant') ? 'assistant' : 'user';
                messages.add(new Map<String, Object>{ 'role' => role, 'content' => m.get('text') });
            }
            // Anthropic requires the conversation to start with a user turn.
            if (messages.isEmpty() || (String) messages[0].get('role') != 'user') {
                messages.add(0, new Map<String, Object>{ 'role' => 'user', 'content' => '(client started a conversation)' });
            }

            // Give Claude today's date so it can resolve "yesterday"/"last week" to a real
            // YYYY-MM-DD for incidentDate (otherwise the date is dropped and Incident Age is wrong).
            String sys = SYSTEM_PROMPT
                + '\n\nToday is ' + Datetime.now().format('yyyy-MM-dd') + ' (YYYY-MM-DD).'
                + ' When the client mentions a relative time such as yesterday, last week, or a few days ago,'
                + ' convert it to an exact calendar date and return it in collected.incidentDate as YYYY-MM-DD.';

            Map<String, Object> body = new Map<String, Object>{
                'model'       => MODEL,
                'max_tokens'  => 600,
                'system'      => sys,
                'tools'       => new List<Object>{ JSON.deserializeUntyped(TOOL_JSON) },
                'tool_choice' => new Map<String, Object>{ 'type' => 'tool', 'name' => 'emit_intake_turn' },
                'messages'    => messages
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Anthropic_Claude/v1/messages');  // existing NC injects the API key
            req.setMethod('POST');
            req.setHeader('content-type', 'application/json');
            req.setHeader('anthropic-version', '2023-06-01');
            req.setTimeout(120000);
            req.setBody(JSON.serialize(body));

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                System.debug('Anthropic call failed: ' + res.getStatusCode() + ' ' + res.getBody());
                return null;
            }

            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            for (Object c : (List<Object>) parsed.get('content')) {
                Map<String, Object> block = (Map<String, Object>) c;
                if (block.get('type') == 'tool_use') {
                    return (Map<String, Object>) block.get('input');
                }
            }
            System.debug('No tool_use block in Anthropic response: ' + res.getBody());
            return null;
        }

        private void finalizeIntake(String leadPhone, Map<String, Object> c) {
            IntakeWrapper w = new IntakeWrapper();
            w.firstName    = str(c.get('firstName'));
            w.lastName     = str(c.get('lastName'));
            w.email        = str(c.get('email'));
            w.phone        = leadPhone;
            w.incidentType = str(c.get('incidentType'));   // constrained to the Intake picklist by the tool enum
            if (String.isBlank(w.incidentType)) w.incidentType = 'Other';   // required field — never leave blank

            String dt = str(c.get('incidentDate'));
            if (dt != null && Pattern.matches('\\d{4}-\\d{2}-\\d{2}', dt)) {
                w.incidentDate = dt;
            }

            // Preserve injuries/treatment/timing context in the description.
            List<String> parts = new List<String>();
            if (str(c.get('description')) != null) parts.add(str(c.get('description')));
            if (str(c.get('injuries'))    != null) parts.add('Injuries: '  + str(c.get('injuries')));
            if (str(c.get('treatment'))   != null) parts.add('Treatment: ' + str(c.get('treatment')));
            if (dt != null && w.incidentDate == null) parts.add('Incident timing: ' + dt);
            w.description = String.join(parts, '\n');

            w.source  = 'SMS';
            w.consent = true;   // they initiated contact by texting in

            PartyIntakeService.ProcessResult pr = PartyIntakeService.process(w);

            // Link the whole conversation to the new Intake for the specialist.
            if (pr != null && pr.intakeId != null) {
                List<TwilioSF__Message__c> thread = [
                    SELECT Id FROM TwilioSF__Message__c
                    WHERE (TwilioSF__From_Number__c = :leadPhone OR TwilioSF__To_Number__c = :leadPhone)
                      AND Intake__c = null
                ];
                for (TwilioSF__Message__c t : thread) t.Intake__c = pr.intakeId;
                if (!thread.isEmpty()) update thread;
            }
        }

        private String str(Object o) {
            if (o == null) return null;
            String s = String.valueOf(o).trim();
            return (s == '' || s.equalsIgnoreCase('null')) ? null : s;
        }
    }
}