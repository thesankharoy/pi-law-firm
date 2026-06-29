public with sharing class IntakeCoPilotController {

    private static final String CLAUDE_MODEL = 'claude-haiku-4-5-20251001';

    private static final String SYSTEM_PROMPT =
        'You are a live co-pilot for a personal-injury (PI) law-firm intake specialist on a phone call. ' +
        'You receive ONE turn of speech from the caller (it may be in any language). Do the following:\n' +
        '1. Give the specialist the single most useful next move: the best qualifying question, an objection-handling line, or the key missing fact. ' +
        'Be concise and specific to PI intake (incident type, injuries, treatment, fault/liability, insurance, statute of limitations, prior representation). Empty if nothing to add.\n' +
        '2. Rate caller sentiment and the running lead fit for a PI case.\n' +
        'Do NOT translate. Respond with ONLY a JSON object, no prose, no code fences, exactly these keys: ' +
        '{"suggestion": "<guidance or empty>", "sentiment": "Positive|Neutral|Negative", "leadFit": "Strong|Moderate|Weak|Red Flag"}';

    public class ContextWrapper {
        @AuraEnabled public String intakeName;
        @AuraEnabled public String clientName;
        @AuraEnabled public String incidentType;
        @AuraEnabled public String status;
    }

    public class CoPilotResult {
        @AuraEnabled public String language;
        @AuraEnabled public String translation;
        @AuraEnabled public String suggestion;
        @AuraEnabled public String sentiment;
        @AuraEnabled public String leadFit;
    }

    @AuraEnabled(cacheable=false)
    public static ContextWrapper getContext(Id intakeId) {
        Intake__c intake = [
            SELECT Name, Status__c, Incident_Type__c, Client__r.Name
            FROM Intake__c
            WHERE Id = :intakeId
            LIMIT 1
        ];
        ContextWrapper ctx = new ContextWrapper();
        ctx.intakeName   = intake.Name;
        ctx.clientName   = intake.Client__r != null ? intake.Client__r.Name : 'Unknown caller';
        ctx.incidentType = intake.Incident_Type__c;
        ctx.status       = intake.Status__c;
        return ctx;
    }

    @AuraEnabled
    public static CoPilotResult analyzeTurn(String transcript, String language, Id intakeId) {
        CoPilotResult result = new CoPilotResult();
        result.language   = String.isBlank(language) ? 'en' : language;
        result.translation = '';
        result.sentiment  = 'Neutral';
        result.leadFit    = 'Moderate';
        if (String.isBlank(transcript)) {
            return result;
        }

        String userText = 'Caller turn:\n"""' + transcript + '"""';

        Map<String, Object> body = new Map<String, Object>{
            'model'      => CLAUDE_MODEL,
            'max_tokens' => 300,
            'system'     => SYSTEM_PROMPT,
            'messages'   => new List<Object>{
                new Map<String, Object>{ 'role' => 'user', 'content' => userText }
            }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Anthropic_Claude/v1/messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('anthropic-version', '2023-06-01');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(body));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException('Claude callout failed (' + res.getStatusCode() + '): ' + res.getBody());
        }
        return parseClaude(res.getBody(), result);
    }

    private static CoPilotResult parseClaude(String responseBody, CoPilotResult fallback) {
        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> content = (List<Object>) root.get('content');
            String text = '';
            if (content != null) {
                for (Object o : content) {
                    Map<String, Object> blk = (Map<String, Object>) o;
                    if (blk.get('type') == 'text' && blk.get('text') != null) {
                        text += (String) blk.get('text');
                    }
                }
            }
            Integer s = text.indexOf('{');
            Integer e = text.lastIndexOf('}');
            if (s < 0 || e < s) {
                return fallback;
            }
            Map<String, Object> j =
                (Map<String, Object>) JSON.deserializeUntyped(text.substring(s, e + 1));

            CoPilotResult r = new CoPilotResult();
            r.language    = fallback.language;
            r.translation = '';
            r.suggestion  = str(j.get('suggestion'), '');
            r.sentiment   = str(j.get('sentiment'), 'Neutral');
            r.leadFit     = str(j.get('leadFit'), 'Moderate');
            return r;
        } catch (Exception ex) {
            return fallback;
        }
    }

    private static String str(Object v, String dflt) {
        return v == null ? dflt : String.valueOf(v);
    }

    @AuraEnabled
    public static void publishMockEvent(Id intakeId, String turnType, String transcript,
                                        String translation, String detectedLanguage,
                                        String suggestion, String sentiment,
                                        String leadFit, Decimal sequence) {
        Co_Pilot_Event__e evt = new Co_Pilot_Event__e(
            Intake_Id__c         = String.valueOf(intakeId),
            Turn_Type__c         = turnType,
            Transcript__c        = transcript,
            Translation__c       = translation,
            Detected_Language__c = detectedLanguage,
            Suggestion__c        = suggestion,
            Sentiment__c         = sentiment,
            Lead_Fit__c          = leadFit,
            Sequence__c          = sequence
        );
        Database.SaveResult sr = EventBus.publish(evt);
        if (!sr.isSuccess()) {
            String msg = '';
            for (Database.Error err : sr.getErrors()) {
                msg += err.getMessage() + ' ';
            }
            throw new AuraHandledException('Failed to publish Co-Pilot event: ' + msg);
        }
    }
}