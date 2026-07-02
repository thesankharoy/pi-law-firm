public without sharing class IntakeEngagementService {
    private static final Set<String> CLOSED = new Set<String>{ 'Converted', 'Turned Down', 'Referred Out' };
    private static final Long BH_DAY_MS = 8L * 60 * 60 * 1000; // 8 BH hours in ms

    // ── Main entry — called by scheduler ──────────────────────────
    public static void evaluate() {
        Engagement_Rule__mdt rule = loadRule();
        if (rule == null || !rule.Active__c)
            return;

        Id bhId = defaultBusinessHoursId();

        List<Intake__c> intakes = [
            SELECT
                Id,
                Name,
                Status__c,
                CreatedDate,
                OwnerId,
                Owner.Name,
                Owner.Email,
                Client__r.Name,
                Incident_Type__c,
                Engagement_Level__c,
                Engagement_Changed_At__c,
                Cold_Notified__c,
                Escalated_To_Manager__c,
                Last_Client_Response_At__c
            FROM Intake__c
            WHERE Owner.Type = 'User' AND Status__c NOT IN :CLOSED
        ];
        if (intakes.isEmpty())
            return;

        // Load manager for escalation
        List<Intake_Manager__c> mgrs = [
            SELECT User__c, User__r.Name, User__r.Email
            FROM Intake_Manager__c
            WHERE Active__c = TRUE
            LIMIT 1
        ];
        Id managerId = mgrs.isEmpty() ? null : mgrs[0].User__c;
        String managerName = mgrs.isEmpty() ? 'Manager' : mgrs[0].User__r.Name;
        String managerEmail = mgrs.isEmpty() ? null : mgrs[0].User__r.Email;

        DateTime now = DateTime.now();

        Integer warmDays = (Integer) rule.Warm_After_BH_Days__c;
        Integer coldDays = (Integer) rule.Cold_After_BH_Days__c;
        Integer deadDays = (Integer) rule.Dead_After_BH_Days__c;
        Integer escalateDays = (Integer) rule.Escalate_After_BH_Days__c;
        Boolean notifyOnCold = rule.Specialist_Notify_On_Cold__c;

        // ── Collections built during the loop ─────────────────────
        List<Intake__c> toUpdate = new List<Intake__c>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Intake__c i : intakes) {
            // ── THE FIX ──────────────────────────────────────────
            // PREVIOUSLY: lastComm = MAX(LastModifiedDate) of completed
            // "Day %" Tasks, falling back to CreatedDate only when NO
            // tasks were ever completed. This meant every specialist
            // task completion — an outbound attempt, not a client
            // response — reset the engagement clock. A fully-worked,
            // completely unanswered 3x3x3 cadence therefore stayed
            // perpetually Hot, while a genuinely-ignored intake correctly
            // fell back to CreatedDate and cooled. The signal was
            // inverted: it measured specialist effort, not client
            // engagement.
            //
            // NOW: lastComm anchors on Last_Client_Response_At__c — a
            // field only ever set when a specialist explicitly confirms
            // the client actually responded (see
            // handleClientResponseUpdate below, fired by
            // TaskEngagementTrigger). If no response has EVER been
            // logged, the anchor falls back to CreatedDate and stays
            // there — completing outbound tasks no longer touches this
            // value at all. A compliant-but-unanswered cadence now
            // correctly accumulates BH-days from the moment the intake
            // was created, crossing Warm → Cold → Dead exactly as
            // intended, and escalating once Cold for long enough.
            DateTime lastComm = i.Last_Client_Response_At__c != null ? i.Last_Client_Response_At__c : i.CreatedDate;

            Long bhMs = BusinessHours.diff(bhId, lastComm, now);
            Decimal bhDays = bhMs / Decimal.valueOf(BH_DAY_MS);

            // Derive new engagement level from BH thresholds
            String newLevel;
            if (bhDays >= deadDays)
                newLevel = 'Dead';
            else if (bhDays >= coldDays)
                newLevel = 'Cold';
            else if (bhDays >= warmDays)
                newLevel = 'Warm';
            else
                newLevel = 'Hot';

            String oldLevel = i.Engagement_Level__c;
            Boolean levelChanged = newLevel != oldLevel;

            Intake__c patch = new Intake__c(Id = i.Id);
            Boolean dirty = false;

            // ── Handle level change ────────────────────────────────
            if (levelChanged) {
                patch.Engagement_Level__c = newLevel;
                patch.Engagement_Changed_At__c = now;
                dirty = true;

                // ── Becoming Cold ──────────────────────────────────
                if (newLevel == 'Cold' && notifyOnCold && !i.Cold_Notified__c) {
                    // Email specialist — once only, gated by checkbox
                    String specEmail = i.Owner?.Email;
                    if (String.isNotBlank(specEmail)) {
                        emails.add(buildSpecialistEmail(i, specEmail, i.Owner?.Name, bhDays));
                    }
                    patch.Cold_Notified__c = true;
                    dirty = true;
                }

                if (newLevel == 'Hot' || newLevel == 'Warm') {
                    patch.Cold_Notified__c = false;
                    patch.Escalated_To_Manager__c = false;
                    dirty = true;
                }
            }

            // ── Escalation check ───────────────────────────────────
            // Fires separately from the level-changed block so it
            // can escalate even on runs where the level didn't just change
            // (e.g. intake was already Cold last run, still Cold now).
            if (
                newLevel == 'Cold' &&
                !i.Escalated_To_Manager__c &&
                managerId != null &&
                i.Engagement_Changed_At__c != null
            ) {
                // BH days the intake has been in Cold state
                Long coldBhMs = BusinessHours.diff(bhId, i.Engagement_Changed_At__c, now);
                Decimal coldBhDays = coldBhMs / Decimal.valueOf(BH_DAY_MS);

                if (coldBhDays >= escalateDays) {
                    // Reassign OwnerId to manager
                    patch.OwnerId = managerId;
                    patch.Escalated_To_Manager__c = true;
                    dirty = true;

                    // Email manager
                    if (String.isNotBlank(managerEmail)) {
                        emails.add(buildManagerEmail(i, managerEmail, managerName, bhDays, coldBhDays));
                    }
                }
            }

            if (dirty)
                toUpdate.add(patch);
        }

        // ════════════════════════════════════════════════════════════
        // SEND EMAILS BEFORE DML
        // Messaging.sendEmail is NOT a callout — safe before or after DML.
        // We send before DML so that if DML fails, emails haven't gone
        // out for a state that was never saved. Acceptable tradeoff.
        // ════════════════════════════════════════════════════════════
        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Engagement email failed: ' + e.getMessage());
            }
        }

        // ── Bulk update all changed intakes in one DML ─────────────
        if (!toUpdate.isEmpty())
            update toUpdate;
    }

    // ── NEW — called by TaskEngagementTrigger ─────────────────────
    // Fires the moment a specialist logs that a client genuinely
    // responded, rather than waiting for the next scheduled evaluate()
    // pass (up to 4 hours away). Snaps the intake straight to Hot and
    // resets the cold/escalation gates so they can fire again if the
    // intake goes quiet a second time. Also cancels any active
    // Re-activation drip enrollment immediately — mirrors the same
    // cleanup evaluate() already performs on a Cold/Dead → Hot/Warm
    // transition, just without the delay.
    public static void handleClientResponseUpdate(List<Task> newTasks, Map<Id, Task> oldMap) {
        Set<Id> candidateIntakeIds = new Set<Id>();

        for (Task t : newTasks) {
            if (t.WhatId == null || t.Client_Responded__c != true)
                continue;
            if (t.Status != 'Completed')
                continue;

            Task old = oldMap != null ? oldMap.get(t.Id) : null;
            Boolean justMarkedResponded = old == null || old.Client_Responded__c != true;
            Boolean justCompleted = old == null || old.Status != 'Completed';

            if (justMarkedResponded || justCompleted) {
                candidateIntakeIds.add(t.WhatId);
            }
        }
        if (candidateIntakeIds.isEmpty())
            return;

        // Filter to real Intake__c parents — harmless no-op for any
        // WhatId that belongs to a different object type.
        Map<Id, Intake__c> intakes = new Map<Id, Intake__c>([SELECT Id FROM Intake__c WHERE Id IN :candidateIntakeIds]);
        if (intakes.isEmpty())
            return;

        DateTime now = DateTime.now();
        List<Intake__c> toUpdate = new List<Intake__c>();
        for (Id intakeId : intakes.keySet()) {
            toUpdate.add(
                new Intake__c(
                    Id = intakeId,
                    Last_Client_Response_At__c = now,
                    Engagement_Level__c = 'Hot',
                    Engagement_Changed_At__c = now,
                    Cold_Notified__c = false,
                    Escalated_To_Manager__c = false
                )
            );
        }
        update toUpdate;

        // No-op if there's no active Re-activation enrollment for these
        // intakes — safe to call unconditionally.
        DripCampaignService.cancelEnrollmentBatch(intakes.keySet());
    }

    // ── Email builders — unchanged ──────────────────────────────────
    private static Messaging.SingleEmailMessage buildSpecialistEmail(
        Intake__c i,
        String toEmail,
        String specName,
        Decimal bhDays
    ) {
        String client = i.Client__r?.Name ?? '—';
        String type = i.Incident_Type__c ?? '—';

        String html = emailWrapper(
            '#fff7ed',
            '#f59e0b',
            'Intake Going Cold — Action Required',
            'Hi ' + (specName ?? 'Specialist') + ',',
            'The following intake has had <strong>no client response for ' +
                bhDays.setScale(1) +
                ' business days</strong>. ' +
                'If you don\'t hear back soon this will be escalated to your manager.',
            new List<String[]>{
                new List<String>{ 'Intake', i.Name },
                new List<String>{ 'Client', client },
                new List<String>{ 'Incident Type', type },
                new List<String>{ 'BH Days No Response', bhDays.setScale(1) + ' days' }
            },
            i.Id
        );

        Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
        em.setToAddresses(new List<String>{ toEmail });
        em.setSubject('Intake Going Cold — ' + i.Name + ' · ' + client);
        em.setHtmlBody(html);
        em.setSaveAsActivity(false);
        return em;
    }

    // ── Manager escalation email ──────────────────────────────────
    private static Messaging.SingleEmailMessage buildManagerEmail(
        Intake__c i,
        String toEmail,
        String mgrName,
        Decimal bhDaysTotal,
        Decimal bhDaysCold
    ) {
        String client = i.Client__r?.Name ?? '—';
        String type = i.Incident_Type__c ?? '—';
        String specName = i.Owner?.Name ?? '—';

        String html = emailWrapper(
            '#fef2f2',
            '#dc2626',
            'Intake Escalated — No Client Response for ' + bhDaysCold.setScale(1) + ' BH Days',
            'Hi ' + mgrName + ',',
            'The following intake has had <strong>no client response for ' +
                bhDaysCold.setScale(1) +
                ' business days</strong> ' +
                'despite the assigned specialist working the full follow-up cadence. ' +
                'It has been <strong>reassigned to you</strong>.',
            new List<String[]>{
                new List<String>{ 'Intake', i.Name },
                new List<String>{ 'Client', client },
                new List<String>{ 'Incident Type', type },
                new List<String>{ 'Was Assigned To', specName },
                new List<String>{ 'Total BH Days No Response', bhDaysTotal.setScale(1) + ' days' },
                new List<String>{ 'Days in Cold', bhDaysCold.setScale(1) + ' days' }
            },
            i.Id
        );

        Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
        em.setToAddresses(new List<String>{ toEmail });
        em.setSubject(
            'Escalated — ' + i.Name + ' · ' + client + ' (' + bhDaysCold.setScale(1) + ' BH days, no response)'
        );
        em.setHtmlBody(html);
        em.setSaveAsActivity(false);
        return em;
    }

    // ════════════════════════════════════════════════════════════════
    // PRIVATE — SHARED EMAIL HTML WRAPPER
    // ════════════════════════════════════════════════════════════════

    private static String emailWrapper(
        String headerBg,
        String accentColor,
        String headline,
        String greeting,
        String body,
        List<String[]> rows,
        Id intakeId
    ) {
        String rowHtml = '';
        for (String[] r : rows) {
            rowHtml +=
                '<tr>' +
                '<td style="padding:10px 14px;background:#f4f6f9;color:#777;' +
                'font-size:11px;text-transform:uppercase;letter-spacing:0.05em;width:38%;' +
                'vertical-align:top;">' +
                r[0] +
                '</td>' +
                '<td style="padding:10px 14px;font-weight:600;color:#04152f;">' +
                (r[1] ?? '—') +
                '</td></tr>';
        }

        String link = URL.getOrgDomainUrl().toExternalForm() + '/' + intakeId;

        return '<!DOCTYPE html><html><body>' +
            '<div style="font-family:Helvetica Neue,Helvetica,Arial,sans-serif;' +
            'max-width:620px;margin:0 auto;border:1px solid #e0e5ee;' +
            'border-radius:8px;overflow:hidden;">' +
            // Header
            '<div style="background:#04152f;padding:20px 28px;">' +
            '<p style="color:#fff;font-size:18px;font-weight:700;margin:0;">' +
            'Delipat Law Group</p>' +
            '<p style="color:#a8bfd6;font-size:11px;margin:4px 0 0;' +
            'text-transform:uppercase;letter-spacing:0.08em;">' +
            'Case Management Platform</p>' +
            '</div>' +
            // Coloured alert bar
            '<div style="background:' +
            headerBg +
            ';' +
            'border-left:4px solid ' +
            accentColor +
            ';padding:14px 20px;">' +
            '<p style="color:' +
            accentColor +
            ';font-weight:700;' +
            'margin:0;font-size:15px;">' +
            headline +
            '</p>' +
            '</div>' +
            // Body
            '<div style="padding:28px;background:#fff;">' +
            '<p style="color:#333;font-size:14px;margin:0 0 12px;">' +
            greeting +
            '</p>' +
            '<p style="color:#333;font-size:14px;margin:0 0 20px;">' +
            body +
            '</p>' +
            '<table style="width:100%;border-collapse:collapse;' +
            'font-size:13px;margin-bottom:24px;">' +
            rowHtml +
            '</table>' +
            '<div style="text-align:center;">' +
            '<a href="' +
            link +
            '" ' +
            'style="display:inline-block;background:#04152f;color:#fff;' +
            'text-decoration:none;padding:14px 32px;border-radius:8px;' +
            'font-size:14px;font-weight:700;">View Intake Record →</a>' +
            '</div></div>' +
            // Footer
            '<div style="padding:16px 28px;background:#f8f9fb;' +
            'border-top:1px solid #e0e5ee;">' +
            '<p style="color:#aaa;font-size:11px;margin:0;">' +
            'Delipat PI Platform · Automated Notification · Do not reply</p>' +
            '</div></div></body></html>';
    }

    // ════════════════════════════════════════════════════════════════
    // PRIVATE — HELPERS
    // ════════════════════════════════════════════════════════════════

    private static Id defaultBusinessHoursId() {
        return [
            SELECT Id
            FROM BusinessHours
            WHERE IsDefault = TRUE
            LIMIT 1
        ]
        .Id;
    }

    private static Engagement_Rule__mdt loadRule() {
        List<Engagement_Rule__mdt> rules = [
            SELECT
                Warm_After_BH_Days__c,
                Cold_After_BH_Days__c,
                Dead_After_BH_Days__c,
                Escalate_After_BH_Days__c,
                Specialist_Notify_On_Cold__c,
                Active__c
            FROM Engagement_Rule__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (!rules.isEmpty())
            return rules[0];

        // Hardcoded fallback if the admin hasn't created the CMDT record yet
        Engagement_Rule__mdt def = new Engagement_Rule__mdt();
        def.Active__c = true;
        def.Warm_After_BH_Days__c = 1;
        def.Cold_After_BH_Days__c = 3;
        def.Dead_After_BH_Days__c = 7;
        def.Escalate_After_BH_Days__c = 2;
        def.Specialist_Notify_On_Cold__c = true;
        return def;
    }
}