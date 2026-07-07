public without sharing class ContactIntelligenceService {
    private static final Integer CACHE_HOURS = 4;

    public class Recommendation {
        @AuraEnabled
        public String primaryChannel;
        @AuraEnabled
        public String primaryChannelIcon;
        // bestTimeWindow is NEVER trusted directly from Claude's JSON and NEVER
        // served as-is from cache. It's always rebuilt fresh — see
        // buildTimeWindowLabel() — from windowStartHour/windowEndHour below,
        // re-validated against the CURRENT moment against the firm's real
        // Business Hours record. This is what stops the widget from ever
        // recommending a contact time that has already passed or that falls
        // outside business hours, even when this whole Recommendation is
        // being served from a multi-hour-old cache.
        @AuraEnabled
        public String bestTimeWindow;
        // Replaces the old single-string `reasoning` field. Each array
        // element is one self-contained bullet — its own reason PLUS the
        // specific evidence/justification behind it — rather than one
        // paragraph. Rendered as an actual bullet list in the LWC.
        @AuraEnabled
        public List<String> reasoningBullets;
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
        // Claude's raw suggested outreach window, 0-23 (24-hour, firm-local
        // time). Kept on the object (and therefore persisted in the cached
        // JSON) so that bestTimeWindow can be recomputed fresh on every read
        // — cache hit or miss — rather than trusting a label baked in at
        // generation time.
        @AuraEnabled
        public Integer windowStartHour;
        @AuraEnabled
        public Integer windowEndHour;
    }

    // ── Business Hours snapshot — queried once per call ──────────────
    // Holds the org's default Business Hours record's per-day Start/End
    // Time fields plus its configured time zone, so the rest of this class
    // can reason about "is the firm open right now" and "what are today's
    // hours" without repeating the query or the timezone-conversion logic.
    private class BusinessHoursInfo {
        Id id;
        String timeZoneSidKey;
        Map<String, Time> startByDay;
        Map<String, Time> endByDay;
    }

    // ── Resolved "right now" relative to Business Hours ──────────────
    // Built once per call from BusinessHoursInfo + the actual current
    // moment. This is what buildTimeWindowLabel() clamps Claude's raw
    // suggested hours against, and what the prompt itself is built from —
    // so the model is always told the TRUE current status in the firm's
    // own time zone, not the running user's personal timezone or the
    // server's default.
    private class TimeWindowContext {
        Boolean isOpenNow;
        String nowLabel; // e.g. "Tuesday, 3:45 PM"
        Integer nowHour; // 0-23, firm-local
        Integer todayCloseHour; // only meaningful when isOpenNow
        String todayCloseLabel;
        String nextOpenLabel; // only meaningful when !isOpenNow
        String scheduleText;
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

        // Business Hours context is needed on EVERY call — cache hit or
        // miss — since bestTimeWindow is always rebuilt fresh (see
        // Recommendation.bestTimeWindow comment above).
        BusinessHoursInfo bhInfo = loadBusinessHoursInfo();
        TimeWindowContext ctx = bhInfo != null ? buildTimeWindowContext(bhInfo) : null;

        // Serve cache when fresh and not force-refreshing
        if (!forceRefresh && isCacheFresh(intake)) {
            Recommendation cached = deserialize(intake.Contact_Intelligence__c);
            // Migration guard: a cache entry written before reasoningBullets
            // existed (old single-string `reasoning` shape) deserializes
            // successfully but leaves reasoningBullets null/empty. Treat
            // that as a cache miss and regenerate, rather than serving a
            // recommendation with no visible reasoning at all.
            if (cached != null && cached.reasoningBullets != null && !cached.reasoningBullets.isEmpty()) {
                cached.fromCache = true;
                // Always rebuilt live — see field comment on bestTimeWindow.
                cached.bestTimeWindow = ctx != null
                    ? buildTimeWindowLabel(cached.windowStartHour, cached.windowEndHour, ctx)
                    : 'Contact during business hours';
                return cached;
            }
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
        String raw = callClaude(buildPrompt(intake, priorTasks, bhInfo, ctx));
        Recommendation rec = parseResponse(raw, ctx);
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

    // ── Business Hours loading + time-window math ──────────────────
    // Queried fresh each call — cheap (single row) and avoids ever acting
    // on a stale snapshot of the firm's configured hours.
    private static BusinessHoursInfo loadBusinessHoursInfo() {
        List<BusinessHours> rows = [
            SELECT
                Id,
                TimeZoneSidKey,
                MondayStartTime,
                MondayEndTime,
                TuesdayStartTime,
                TuesdayEndTime,
                WednesdayStartTime,
                WednesdayEndTime,
                ThursdayStartTime,
                ThursdayEndTime,
                FridayStartTime,
                FridayEndTime,
                SaturdayStartTime,
                SaturdayEndTime,
                SundayStartTime,
                SundayEndTime
            FROM BusinessHours
            WHERE IsDefault = TRUE
            LIMIT 1
        ];
        if (rows.isEmpty())
            return null;

        BusinessHours bh = rows[0];
        BusinessHoursInfo info = new BusinessHoursInfo();
        info.id = bh.Id;
        info.timeZoneSidKey = bh.TimeZoneSidKey;
        info.startByDay = new Map<String, Time>{
            'Monday' => bh.MondayStartTime,
            'Tuesday' => bh.TuesdayStartTime,
            'Wednesday' => bh.WednesdayStartTime,
            'Thursday' => bh.ThursdayStartTime,
            'Friday' => bh.FridayStartTime,
            'Saturday' => bh.SaturdayStartTime,
            'Sunday' => bh.SundayStartTime
        };
        info.endByDay = new Map<String, Time>{
            'Monday' => bh.MondayEndTime,
            'Tuesday' => bh.TuesdayEndTime,
            'Wednesday' => bh.WednesdayEndTime,
            'Thursday' => bh.ThursdayEndTime,
            'Friday' => bh.FridayEndTime,
            'Saturday' => bh.SaturdayEndTime,
            'Sunday' => bh.SundayEndTime
        };
        return info;
    }

    // Builds the "right now" snapshot used both in the prompt sent to
    // Claude and in buildTimeWindowLabel()'s clamping logic. Uses
    // Datetime.format(pattern, timeZoneSidKey) throughout — NEVER
    // Date.today() or DateTime.now().date() — so this is always evaluated
    // in the Business Hours record's own configured time zone, regardless
    // of the running user's personal Salesforce timezone. This project has
    // been bitten hard before by exactly this kind of timezone mismatch
    // (see the earlier 3x3x3 follow-up scheduler fix); this class doesn't
    // repeat that mistake.
    private static TimeWindowContext buildTimeWindowContext(BusinessHoursInfo info) {
        TimeWindowContext ctx = new TimeWindowContext();
        DateTime nowDt = DateTime.now();

        ctx.scheduleText = buildScheduleText(info);
        ctx.isOpenNow = BusinessHours.isWithin(info.id, nowDt);
        ctx.nowLabel = nowDt.format('EEEE, h:mm a', info.timeZoneSidKey);
        ctx.nowHour = Integer.valueOf(nowDt.format('H', info.timeZoneSidKey));

        if (ctx.isOpenNow) {
            String todayName = nowDt.format('EEEE', info.timeZoneSidKey);
            Time closeT = info.endByDay.get(todayName);
            ctx.todayCloseHour = closeT != null ? closeT.hour() : 23;
            ctx.todayCloseLabel = closeT != null ? formatTimeLabel(closeT) : 'end of day';
        } else {
            DateTime nextOpen = BusinessHours.nextStartDate(info.id, nowDt);
            ctx.nextOpenLabel = nextOpen.format('EEEE, h:mm a', info.timeZoneSidKey);
        }
        return ctx;
    }

    private static String buildScheduleText(BusinessHoursInfo info) {
        List<String> days = new List<String>{
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
            'Sunday'
        };
        List<String> lines = new List<String>();
        for (String d : days) {
            Time s = info.startByDay.get(d);
            Time e = info.endByDay.get(d);
            lines.add(
                s == null || e == null ? d + ': Closed' : d + ': ' + formatTimeLabel(s) + ' – ' + formatTimeLabel(e)
            );
        }
        return String.join(lines, '\n');
    }

    private static String formatTimeLabel(Time t) {
        if (t == null)
            return null;
        Integer h = t.hour();
        Integer m = t.minute();
        String ampm = h < 12 ? 'AM' : 'PM';
        Integer h12 = Math.mod(h, 12);
        if (h12 == 0)
            h12 = 12;
        String mLabel = m == 0 ? '00' : (m < 10 ? '0' + m : String.valueOf(m));
        return h12 + ':' + mLabel + ' ' + ampm;
    }

    private static String hourToLabel(Integer h) {
        Integer h12 = Math.mod(h, 12);
        if (h12 == 0)
            h12 = 12;
        String ampm = h < 12 ? 'AM' : 'PM';
        return h12 + ':00 ' + ampm;
    }

    // ── The single source of truth for bestTimeWindow's text ────────
    // Ignores whatever freeform time text Claude might be tempted to
    // produce entirely — Claude only ever contributes windowStartHour/
    // windowEndHour as raw integers, and THIS method is what turns those
    // into the label the specialist actually sees, after clamping them
    // against the CURRENT moment. If the firm is closed right now — even
    // if it was open when this recommendation was originally generated —
    // this always returns the deterministic "next opening" answer instead
    // of a stale or out-of-hours suggestion.
    private static String buildTimeWindowLabel(Integer aiStartHour, Integer aiEndHour, TimeWindowContext ctx) {
        if (!ctx.isOpenNow) {
            return 'Next opening — ' + ctx.nextOpenLabel;
        }

        Integer startH = aiStartHour != null ? aiStartHour : ctx.nowHour;
        Integer endH = aiEndHour != null ? aiEndHour : ctx.todayCloseHour;

        // Clamp into [nowHour, todayCloseHour] — never before now, never
        // past today's close.
        if (startH < ctx.nowHour)
            startH = ctx.nowHour;
        if (startH > ctx.todayCloseHour)
            startH = ctx.todayCloseHour;
        if (endH > ctx.todayCloseHour)
            endH = ctx.todayCloseHour;
        if (endH <= startH)
            endH = Math.min(ctx.todayCloseHour, startH + 1);

        if (endH <= startH) {
            // We're at (or past) closing hour already — nothing meaningful
            // left to window today.
            return 'Right now — closing soon (' + ctx.todayCloseLabel + ')';
        }
        if (startH <= ctx.nowHour) {
            return 'Right now, through ' + ctx.todayCloseLabel + ' close';
        }
        return hourToLabel(startH) + '–' + hourToLabel(endH) + ' today (before ' + ctx.todayCloseLabel + ' close)';
    }

    private static String buildPrompt(
        Intake__c intake,
        List<Task> priorTasks,
        BusinessHoursInfo bhInfo,
        TimeWindowContext ctx
    ) {
        String leadDay = bhInfo != null
            ? intake.CreatedDate.format('EEEE', bhInfo.timeZoneSidKey)
            : intake.CreatedDate.format('EEEE');
        String leadTime = bhInfo != null
            ? intake.CreatedDate.format('h:mm a', bhInfo.timeZoneSidKey)
            : intake.CreatedDate.format('h:mm a');
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

        // ── Business Hours section — NEW ─────────────────────────────
        // This is the fix for the out-of-hours recommendation bug: the
        // model previously received only a bare "current time" with no
        // notion of the firm's actual operating hours, so it had nothing
        // to ground a business-hours-appropriate suggestion against. It
        // now gets the full weekly schedule plus an explicit open/closed
        // verdict for right now, and a hard numeric range to stay within.
        String businessHoursSection;
        if (ctx == null) {
            businessHoursSection = 'BUSINESS HOURS: Not configured for this org — assume a standard weekday 9am-6pm schedule and do not suggest contacting the lead late at night or on a weekend.\n';
        } else {
            businessHoursSection =
                'FIRM BUSINESS HOURS (all times below are in the firm\'s own local time zone):\n' +
                ctx.scheduleText +
                '\n\n' +
                'RIGHT NOW: ' +
                ctx.nowLabel +
                ' — the firm is currently ' +
                (ctx.isOpenNow ? 'OPEN' : 'CLOSED') +
                '.\n' +
                (ctx.isOpenNow
                    ? ('We remain open until ' + ctx.todayCloseLabel + ' today.\n')
                    : ('We are closed right now. The next opening is ' + ctx.nextOpenLabel + '.\n'));
        }

        return 'You are an expert PI law firm intake advisor.\n\n' +
            businessHoursSection +
            '\n' +
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
            '- Lead submission time is a signal of when they tend to be reachable, but any outreach you suggest MUST still fall within the firm\'s business hours above — never recommend contacting a lead outside business hours, late at night, or on a day the firm is closed\n' +
            '- If a channel has many COMPLETED tasks, it is working — recommend it\n' +
            '- If calls are going unanswered repeatedly, shift to SMS or a different time within business hours\n' +
            '- PI prospects are anxious, shopping multiple firms; warmth and speed win\n' +
            '- Incident severity and description context should influence urgency tone\n\n' +
            'Based on ALL of the above, decide the best channel and time window.\n' +
            'IMPORTANT: Return ONLY valid JSON. No markdown, no explanation outside JSON:\n' +
            '{\n' +
            '  "primaryChannel": "SMS|Phone|Email",\n' +
            '  "primaryChannelIcon": "💬|📞|✉️",\n' +
            '  "confidence": "high|medium|low",\n' +
            '  "reasoningBullets": ["3 to 5 short bullet strings. EACH bullet must state ONE distinct reason PLUS the specific evidence or justification behind it (e.g. prior attempt data, incident details, channel effectiveness stats, submission timing, business-hours status). Never write a single paragraph — every array element must stand alone as its own bullet."],\n' +
            '  "windowStartHour": 0,\n' +
            '  "windowEndHour": 0,\n' +
            '  "callHint": "one short action hint for the specialist on the Call task",\n' +
            '  "smsHint": "one short action hint for the specialist on the SMS task",\n' +
            '  "emailHint": "one short action hint for the specialist on the Email task"\n' +
            '}\n\n' +
            'windowStartHour and windowEndHour are integers 0-23 (24-hour, firm-local time) for your suggested outreach window. ' +
            (ctx != null && ctx.isOpenNow
                ? ('They MUST fall between ' +
                  ctx.nowHour +
                  ' and ' +
                  ctx.todayCloseHour +
                  ' — i.e. sometime later today, before the firm closes.')
                : 'The firm is currently closed, so these two fields will not be shown to the specialist as-is — the actual next-opening time is computed separately. Still provide your best-guess hours for internal consistency.');
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

    private static Recommendation parseResponse(String raw, TimeWindowContext ctx) {
        try {
            String clean = raw.replaceAll('(?s)```json', '').replaceAll('```', '').trim();
            Recommendation rec = (Recommendation) JSON.deserialize(clean, Recommendation.class);
            if (rec.reasoningBullets == null || rec.reasoningBullets.isEmpty()) {
                return buildFallback(ctx);
            }
            rec.bestTimeWindow = ctx != null
                ? buildTimeWindowLabel(rec.windowStartHour, rec.windowEndHour, ctx)
                : 'Contact during business hours';
            return rec;
        } catch (Exception e) {
            return buildFallback(ctx);
        }
    }

    // Fallback now also goes through buildTimeWindowLabel() rather than a
    // hardcoded "As soon as possible" string — that hardcoded text was
    // itself capable of being wrong outside business hours. The fallback
    // path is exactly as business-hours-aware as the normal path now.
    private static Recommendation buildFallback(TimeWindowContext ctx) {
        Recommendation fb = new Recommendation();
        fb.primaryChannel = 'Phone';
        fb.primaryChannelIcon = '📞';
        fb.confidence = 'low';
        fb.reasoningBullets = new List<String>{
            'Recommendation service is temporarily unavailable, so this is a safe default rather than a lead-specific, data-driven pick.',
            'Phone has the highest conversion rate for PI intake outreach generally — calling first is the safest default absent personalized data.',
            'Refresh this card once the recommendation service recovers for a suggestion based on this lead\'s actual history and incident details.'
        };
        fb.callHint = 'Highest-conversion channel — try this first';
        fb.smsHint = '98% open rate — good backup if the call goes unanswered';
        fb.emailHint = 'Best for documentation and follow-through';
        fb.windowStartHour = ctx != null ? ctx.nowHour : null;
        fb.windowEndHour = ctx != null ? ctx.todayCloseHour : null;
        fb.bestTimeWindow = ctx != null
            ? buildTimeWindowLabel(fb.windowStartHour, fb.windowEndHour, ctx)
            : 'Contact during business hours';
        return fb;
    }
}