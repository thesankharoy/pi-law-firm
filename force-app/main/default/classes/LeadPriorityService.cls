public without sharing class LeadPriorityService {
    private static final Integer CACHE_MINUTES = 10;
    private static final Set<String> CLOSED = new Set<String>{ 'Converted', 'Turned Down', 'Referred Out' };

    // ── Public entry points ────────────────────────────────────────
    public static void rankIntakes(Id userId) {
        run(userId, false);
    }

    public static void forceRankIntakes(Id userId) {
        run(userId, true);
    }

    public static Boolean isCacheFresh(Id userId) {
        List<Intake_Specialist__c> specs = [
            SELECT Priority_Ranking_At__c
            FROM Intake_Specialist__c
            WHERE User__c = :userId
            LIMIT 1
        ];
        if (specs.isEmpty() || specs[0].Priority_Ranking_At__c == null)
            return false;
        return DateTime.now() < specs[0].Priority_Ranking_At__c.addMinutes(CACHE_MINUTES);
    }

    // ── Core ───────────────────────────────────────────────────────
    private static void run(Id userId, Boolean forceRefresh) {
        // Cache check — skip Claude if ranking is fresh
        if (!forceRefresh && isCacheFresh(userId))
            return;

        List<Intake__c> intakes = [
            SELECT
                Id,
                Name,
                Status__c,
                Source__c,
                CreatedDate,
                Incident_Type__c,
                Incident_Description__c,
                Incident_Date__c,
                Incident_Age__c,
                Injury_Severity__c,
                AI_Summary__c,
                AI_Recommended_Action__c,
                Priority__c,
                Priority_Rank__c
            FROM Intake__c
            WHERE OwnerId = :userId AND Status__c NOT IN :CLOSED
            ORDER BY CreatedDate ASC
        ];
        if (intakes.isEmpty())
            return;

        // Task completion counts per intake
        Map<Id, Map<String, Integer>> taskMap = buildTaskMap(new Map<Id, Intake__c>(intakes).keySet());

        // Build compact payload for Claude
        List<Map<String, Object>> payload = new List<Map<String, Object>>();
        for (Intake__c i : intakes) {
            Long msOld = DateTime.now().getTime() - i.CreatedDate.getTime();
            Decimal hoursOld = (msOld / 3600000.0).setScale(1);
            Map<String, Integer> tm = taskMap.containsKey(i.Id)
                ? taskMap.get(i.Id)
                : new Map<String, Integer>{ 'Call_Done' => 0, 'SMS_Done' => 0, 'Email_Done' => 0, 'Overdue' => 0 };

            payload.add(
                new Map<String, Object>{
                    'id' => i.Id,
                    'name' => i.Name,
                    'status' => i.Status__c,
                    'source' => i.Source__c ?? 'Unknown',
                    'hoursOld' => hoursOld,
                    'incidentType' => i.Incident_Type__c ?? 'Unknown',
                    'incidentAge' => i.Incident_Age__c ?? 'Unknown',
                    'incidentDate' => i.Incident_Date__c != null
                        ? DateTime.newInstance(i.Incident_Date__c, Time.newInstance(0, 0, 0, 0)).format('MMM d, yyyy')
                        : 'Unknown',
                    'description' => String.isNotBlank(i.Incident_Description__c)
                        ? i.Incident_Description__c.abbreviate(200)
                        : '',
                    'severity' => i.Injury_Severity__c ?? 'Unknown',
                    'summary' => String.isNotBlank(i.AI_Summary__c) ? i.AI_Summary__c.abbreviate(120) : '',
                    'nextAction' => String.isNotBlank(i.AI_Recommended_Action__c)
                        ? i.AI_Recommended_Action__c.abbreviate(100)
                        : '',
                    'callsDone' => tm.get('Call_Done'),
                    'smsDone' => tm.get('SMS_Done'),
                    'emailDone' => tm.get('Email_Done'),
                    'overdueTasks' => tm.get('Overdue')
                }
            );
        }

        // ── CALLOUT FIRST — no DML before this line ────────────────
        String raw = callClaude(buildPrompt(payload));

        // ── PARSE ──────────────────────────────────────────────────
        List<Map<String, Object>> ranked = parseResponse(raw);

        // ── DML: bulk update Intake fields ─────────────────────────
        Map<String, Map<String, Object>> rankById = new Map<String, Map<String, Object>>();
        for (Map<String, Object> r : ranked) {
            rankById.put((String) r.get('id'), r);
        }

        List<Intake__c> toUpdate = new List<Intake__c>();
        for (Intake__c i : intakes) {
            Map<String, Object> r = rankById.get(i.Id);
            if (r == null)
                continue;
            toUpdate.add(
                new Intake__c(
                    Id = i.Id,
                    Priority__c = (String) r.get('priority'),
                    Priority_Rank__c = r.get('priorityRank') != null
                        ? Decimal.valueOf(String.valueOf(r.get('priorityRank')))
                        : null,
                    Is_At_Risk__c = r.get('isAtRisk') == true,
                    Risk_Reason__c = (String) r.get('riskReason')
                )
            );
        }
        if (!toUpdate.isEmpty())
            update toUpdate;

        // Update cache timestamp on specialist record
        List<Intake_Specialist__c> specs = [SELECT Id FROM Intake_Specialist__c WHERE User__c = :userId LIMIT 1];
        if (!specs.isEmpty()) {
            specs[0].Priority_Ranking_At__c = DateTime.now();
            update specs[0];
        }
    }

    // ── Task completion + overdue per intake ───────────────────────
    private static Map<Id, Map<String, Integer>> buildTaskMap(Set<Id> intakeIds) {
        Map<Id, Map<String, Integer>> result = new Map<Id, Map<String, Integer>>();
        for (Task t : [
            SELECT WhatId, Type, Status, ActivityDate
            FROM Task
            WHERE WhatId IN :intakeIds AND Subject LIKE 'Day %'
        ]) {
            if (!result.containsKey(t.WhatId)) {
                result.put(
                    t.WhatId,
                    new Map<String, Integer>{ 'Call_Done' => 0, 'SMS_Done' => 0, 'Email_Done' => 0, 'Overdue' => 0 }
                );
            }
            Map<String, Integer> m = result.get(t.WhatId);
            if (t.Status == 'Completed') {
                String key = (t.Type ?? '') + '_Done';
                if (m.containsKey(key))
                    m.put(key, m.get(key) + 1);
            }
            Boolean overdue =
                t.Status == 'Incomplete' ||
                (t.Status == 'Not Started' &&
                t.ActivityDate != null &&
                t.ActivityDate < Date.today());
            if (overdue)
                m.put('Overdue', m.get('Overdue') + 1);
        }
        return result;
    }

    // ── Prompt ────────────────────────────────────────────────────
    private static String buildPrompt(List<Map<String, Object>> payload) {
        return 'You are an expert PI law firm intake advisor.\n\n' +
            'CURRENT TIME: ' +
            DateTime.now().format('EEEE, h:mm a z') +
            '\n\n' +
            'TASK: Score and rank ' +
            payload.size() +
            ' open PI leads for a specialist.\n\n' +
            'LEADS (JSON array):\n' +
            JSON.serialize(payload) +
            '\n\n' +
            'SCORING CRITERIA:\n' +
            '- Speed urgency: under 4h old = highest urgency\n' +
            '- Case value: wrongful death/truck > MVA > slip-fall > other\n' +
            '- Source: referral > inbound phone > web > social\n' +
            '- Incident description severity — read it and weight accordingly\n' +
            '- Incident age (statute of limitations risk) — older incident = more urgent\n' +
            '- No contact yet + aging fast = Critical priority\n' +
            '- Many completed tasks = making progress, slightly lower urgency\n' +
            '- Overdue tasks = serious risk indicator\n\n' +
            'AT-RISK RULES (isAtRisk = true if ANY apply):\n' +
            '- hoursOld > 8 AND callsDone = 0 → critical\n' +
            '- overdueTasks >= 2 → high\n' +
            '- hoursOld > 48 AND status still New or Assigned → high\n' +
            '- High-value type AND zero contact on any channel → critical\n' +
            '- hoursOld > 4 AND no contact at all → medium\n\n' +
            'Return ONLY a valid JSON array. No markdown, no text outside the array:\n' +
            '[\n' +
            '  {\n' +
            '    "id": "salesforceId",\n' +
            '    "priority": "High|Medium|Low",\n' +
            '    "priorityRank": 85,\n' +
            '    "isAtRisk": true,\n' +
            '    "riskReason": "≤60 chars why slipping or null"\n' +
            '  }\n' +
            ']';
    }

    // ── Callout ───────────────────────────────────────────────────
    private static String callClaude(String prompt) {
        Map<String, Object> body = new Map<String, Object>{
            'model' => 'claude-sonnet-4-6',
            'max_tokens' => 1000,
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

    // ── Parse ─────────────────────────────────────────────────────
    private static List<Map<String, Object>> parseResponse(String raw) {
        try {
            String clean = raw.replaceAll('(?s)```json', '').replaceAll('```', '').trim();
            List<Object> parsed = (List<Object>) JSON.deserializeUntyped(clean);
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            for (Object o : parsed)
                result.add((Map<String, Object>) o);
            return result;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Priority parse failed: ' + e.getMessage());
            return new List<Map<String, Object>>();
        }
    }
}