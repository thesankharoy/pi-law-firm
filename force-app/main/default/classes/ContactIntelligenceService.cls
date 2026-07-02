public without sharing class ContactIntelligenceService {
    private static final Integer CACHE_HOURS = 4;

    public class Recommendation {
        @AuraEnabled
        public String primaryChannel;
        @AuraEnabled
        public String primaryChannelIcon;
        @AuraEnabled
        public String bestTimeWindow;
        @AuraEnabled
        public String reasoning;
        @AuraEnabled
        public String confidence;
        @AuraEnabled
        public String callHint;
        @AuraEnabled
        public String smsHint;
        @AuraEnabled
        public String emailHint;
        @AuraEnabled
        public String generatedAt;
        @AuraEnabled
        public Boolean fromCache;
    }

    // ── Public entry points ────────────────────────────────────────
    public static Recommendation getRecommendation(Id intakeId) {
        return run(intakeId, false);
    }

    public static Recommendation refreshRecommendation(Id intakeId) {
        return run(intakeId, true);
    }

    // ── Internal: forceRefresh bypasses cache without pre-DML ──────
    private static Recommendation run(Id intakeId, Boolean forceRefresh) {
        Intake__c intake = [
            SELECT
                Id,
                Name,
                CreatedDate,
                Source__c,
                Status__c,
                Incident_Type__c,
                Incident_Description__c,
                Incident_Date__c,
                Incident_Age__c,
                Incident_Location__Street__s,
                Incident_Location__City__s,
                Incident_Location__StateCode__s,
                Incident_Location__CountryCode__s,
                AI_Recommended_Action__c,
                AI_Summary__c,
                Contact_Intelligence__c,
                Contact_Intelligence_At__c,
                Client__r.Phone,
                Client__r.MobilePhone,
                Client__r.Email
            FROM Intake__c
            WHERE Id = :intakeId
            LIMIT 1
        ];

        // Serve cache when fresh and not force-refreshing
        if (!forceRefresh && isCacheFresh(intake)) {
            Recommendation cached = deserialize(intake.Contact_Intelligence__c);
            cached.fromCache = true;
            return cached;
        }

        // Prior task history — used for channel pattern analysis
        List<Task> priorTasks = [
            SELECT Subject, ActivityDate, Status, Type
            FROM Task
            WHERE WhatId = :intakeId AND Subject LIKE 'Day %'
            ORDER BY ActivityDate ASC
            LIMIT 30
        ];

        // ── ALL CALLOUTS BEFORE DML ────────────────────────────────
        String raw = callClaude(buildPrompt(intake, priorTasks));
        Recommendation rec = parseResponse(raw);
        rec.generatedAt = DateTime.now().format('MMM d, h:mm a');
        rec.fromCache = false;

        // ── DML AFTER callout — safe ───────────────────────────────
        intake.Contact_Intelligence__c = JSON.serialize(rec);
        intake.Contact_Intelligence_At__c = DateTime.now();
        update intake;

        return rec;
    }

    // ── Open tasks for the LWC task list ──────────────────────────
    public static List<Map<String, Object>> getIntakeTasks(Id intakeId) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Task t : [
            SELECT Id, Subject, ActivityDate, Status, Type
            FROM Task
            WHERE WhatId = :intakeId AND Subject LIKE 'Day %' AND Status NOT IN ('Completed', 'Cancelled')
            ORDER BY ActivityDate ASC, Type ASC
        ]) {
            result.add(
                new Map<String, Object>{
                    'id' => t.Id,
                    'subject' => t.Subject,
                    'activityDate' => t.ActivityDate != null
                        ? DateTime.newInstance(t.ActivityDate, Time.newInstance(0, 0, 0, 0)).format('MMM d')
                        : '',
                    'status' => t.Status,
                    'type' => t.Type
                }
            );
        }
        return result;
    }

    // ── Helpers ────────────────────────────────────────────────────
    private static Boolean isCacheFresh(Intake__c intake) {
        if (String.isBlank(intake.Contact_Intelligence__c))
            return false;
        if (intake.Contact_Intelligence_At__c == null)
            return false;
        return DateTime.now() < intake.Contact_Intelligence_At__c.addHours(CACHE_HOURS);
    }

    // Renamed from 'json' to 'jsonString' — 'json' collides with System.JSON class
    private static Recommendation deserialize(String jsonString) {
        return (Recommendation) JSON.deserialize(jsonString, Recommendation.class);
    }

    private static String buildPrompt(Intake__c intake, List<Task> priorTasks) {
        DateTime now = DateTime.now();
        String leadDay = intake.CreatedDate.format('EEEE');
        String leadTime = intake.CreatedDate.format('h:mm a');
        Boolean hasPhone =
            String.isNotBlank(intake.Client__r?.Phone) || String.isNotBlank(intake.Client__r?.MobilePhone);
        Boolean hasEmail = String.isNotBlank(intake.Client__r?.Email);

        // Primary phone for contact (prefer MobilePhone as more reliable for SMS)
        String phoneDisplay = String.isNotBlank(intake.Client__r?.MobilePhone)
            ? intake.Client__r.MobilePhone
            : (String.isNotBlank(intake.Client__r?.Phone) ? intake.Client__r.Phone : 'Not on file');

        // Incident location — parse compound address sub-fields
        List<String> locParts = new List<String>();
        if (String.isNotBlank(intake.Incident_Location__Street__s))
            locParts.add(intake.Incident_Location__Street__s);
        if (String.isNotBlank(intake.Incident_Location__City__s))
            locParts.add(intake.Incident_Location__City__s);
        if (String.isNotBlank(intake.Incident_Location__StateCode__s))
            locParts.add(intake.Incident_Location__StateCode__s);
        if (String.isNotBlank(intake.Incident_Location__CountryCode__s))
            locParts.add(intake.Incident_Location__CountryCode__s);
        String incidentLocation = locParts.isEmpty() ? 'Not specified' : String.join(locParts, ', ');

        // Incident date and days since
        String incidentDateStr = 'Not specified';
        if (intake.Incident_Date__c != null) {
            incidentDateStr = DateTime.newInstance(intake.Incident_Date__c, Time.newInstance(0, 0, 0, 0))
                .format('MMM d, yyyy');
        }

        // Prior task channel analysis — key for point 4 (learn from past attempts)
        Map<String, Integer> completedByType = new Map<String, Integer>{ 'Call' => 0, 'SMS' => 0, 'Email' => 0 };
        Map<String, Integer> totalByType = new Map<String, Integer>{ 'Call' => 0, 'SMS' => 0, 'Email' => 0 };
        List<String> attemptLines = new List<String>();

        for (Task t : priorTasks) {
            String tType = t.Type != null ? t.Type : '';
            if (totalByType.containsKey(tType)) {
                totalByType.put(tType, totalByType.get(tType) + 1);
                if (t.Status == 'Completed') {
                    completedByType.put(tType, completedByType.get(tType) + 1);
                }
            }
            attemptLines.add(
                '• ' +
                    t.Subject +
                    ' | Channel: ' +
                    (String.isNotBlank(tType) ? tType : '?') +
                    ' | Status: ' +
                    t.Status +
                    ' | Date: ' +
                    (t.ActivityDate != null
                        ? DateTime.newInstance(t.ActivityDate, Time.newInstance(0, 0, 0, 0)).format('MMM d')
                        : '?')
            );
        }

        // Build channel effectiveness summary for the prompt
        String channelPattern = '';
        for (String ch : new List<String>{ 'Call', 'SMS', 'Email' }) {
            Integer done = completedByType.get(ch);
            Integer total = totalByType.get(ch);
            if (total > 0) {
                channelPattern += ch + ': ' + done + '/' + total + ' completed. ';
            }
        }
        if (String.isBlank(channelPattern))
            channelPattern = 'No prior attempts.';

        String attempts = attemptLines.isEmpty()
            ? 'None — this is the first attempt.'
            : String.join(attemptLines, '\n');

        // Optional AI context fields — include only if populated
        String aiContext = '';
        if (String.isNotBlank(intake.AI_Summary__c)) {
            aiContext += '- AI Summary: ' + intake.AI_Summary__c.abbreviate(300) + '\n';
        }
        if (String.isNotBlank(intake.AI_Recommended_Action__c)) {
            aiContext += '- Previous AI Recommended Action: ' + intake.AI_Recommended_Action__c.abbreviate(200) + '\n';
        }

        return 'You are an expert PI law firm intake advisor.\n\n' +
            'CURRENT TIME: ' +
            now.format('EEEE, h:mm a z') +
            '\n\n' +
            'LEAD PROFILE:\n' +
            '- Lead submitted: ' +
            leadDay +
            ' at ' +
            leadTime +
            '\n' +
            '- Incident type: ' +
            (String.isNotBlank(intake.Incident_Type__c) ? intake.Incident_Type__c : 'Unknown') +
            '\n' +
            '- Incident date: ' +
            incidentDateStr +
            '\n' +
            '- Incident age (days): ' +
            (intake.Incident_Age__c != null ? intake.Incident_Age__c : 'Unknown') +
            '\n' +
            '- Incident location: ' +
            incidentLocation +
            '\n' +
            '- Lead source: ' +
            (String.isNotBlank(intake.Source__c) ? intake.Source__c : 'Unknown') +
            '\n' +
            '- Phone on file: ' +
            phoneDisplay +
            '\n' +
            '- Email on file: ' +
            (hasEmail ? intake.Client__r.Email : 'None') +
            '\n' +
            (String.isNotBlank(intake.Incident_Description__c)
                ? '- Incident description: ' + intake.Incident_Description__c.abbreviate(400) + '\n'
                : '') +
            (String.isNotBlank(aiContext) ? aiContext : '') +
            '\nCHANNEL EFFECTIVENESS FROM PRIOR ATTEMPTS:\n' +
            channelPattern +
            '\n\n' +
            'PRIOR CONTACT ATTEMPTS:\n' +
            attempts +
            '\n\n' +
            'KEY DOMAIN FACTS:\n' +
            '- SMS: 98% open rate, most read within 3 minutes — best for quick touch\n' +
            '- Phone: highest-intent PI channel; voice builds trust and urgency\n' +
            '- Email: lowest open rate, best for documentation and async follow-up\n' +
            '- Lead submission time is the strongest proxy for when they are awake\n' +
            '- If a channel has many COMPLETED tasks, it is working — recommend it\n' +
            '- If calls are going unanswered repeatedly, shift to SMS or different time\n' +
            '- PI prospects are anxious, shopping multiple firms; warmth and speed win\n' +
            '- Incident severity and description context should influence urgency tone\n\n' +
            'Based on ALL of the above, decide the best channel and time window.\n' +
            'IMPORTANT: Return ONLY valid JSON. No markdown, no explanation outside JSON:\n' +
            '{\n' +
            '  "primaryChannel": "SMS|Phone|Email",\n' +
            '  "primaryChannelIcon": "💬|📞|✉️",\n' +
            '  "bestTimeWindow": "concise label e.g. This evening 6–8pm or Right now",\n' +
            '  "confidence": "high|medium|low",\n' +
            '  "reasoning": "2-3 sentences explaining the recommendation using the data above",\n' +
            '  "callHint": "one short action hint for the specialist on the Call task",\n' +
            '  "smsHint": "one short action hint for the specialist on the SMS task",\n' +
            '  "emailHint": "one short action hint for the specialist on the Email task"\n' +
            '}';
    }

    private static String callClaude(String prompt) {
        Map<String, Object> body = new Map<String, Object>{
            'model' => 'claude-haiku-4-5-20251001',
            'max_tokens' => 600,
            'messages' => new List<Object>{ new Map<String, Object>{ 'role' => 'user', 'content' => prompt } }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Anthropic_Claude/v1/messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('anthropic-version', '2023-06-01');
        req.setBody(JSON.serialize(body));
        req.setTimeout(30000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException('Claude API error ' + res.getStatusCode() + ': ' + res.getBody());
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> content = (List<Object>) parsed.get('content');
        Map<String, Object> first = (Map<String, Object>) content[0];
        return (String) first.get('text');
    }

    private static Recommendation parseResponse(String raw) {
        try {
            String clean = raw.replaceAll('(?s)```json', '').replaceAll('```', '').trim();
            return (Recommendation) JSON.deserialize(clean, Recommendation.class);
        } catch (Exception e) {
            Recommendation fb = new Recommendation();
            fb.primaryChannel = 'Phone';
            fb.primaryChannelIcon = '📞';
            fb.bestTimeWindow = 'As soon as possible';
            fb.confidence = 'low';
            fb.reasoning = 'Recommendation temporarily unavailable. Phone has the highest PI conversion rate — call first.';
            fb.callHint = 'Highest conversion channel — try first';
            fb.smsHint = '98% open rate — send a warm intro text';
            fb.emailHint = 'Good for follow-through and documentation';
            return fb;
        }
    }
}