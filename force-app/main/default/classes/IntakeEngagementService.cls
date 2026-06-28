public without sharing class IntakeEngagementService {
    private static final Set<String> CLOSED = new Set<String>{ 'Converted', 'Turned Down', 'Referred Out' };
    private static final Long BH_DAY_MS = 8L * 60 * 60 * 1000; // 8 BH hours in ms

    // ── Main entry — called by EngagementLevelScheduler ──────────
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
                Escalated_To_Manager__c
            FROM Intake__c
            WHERE Owner.Type = 'User' AND Status__c NOT IN :CLOSED
        ];
        if (intakes.isEmpty())
            return;

        // Last completed task date per intake — proxy for last communication
        Set<Id> ids = new Map<Id, Intake__c>(intakes).keySet();
        Map<Id, DateTime> lastCommMap = new Map<Id, DateTime>();
        for (AggregateResult ar : [
            SELECT WhatId wid, MAX(LastModifiedDate) lastComm
            FROM Task
            WHERE WhatId IN :ids AND Status = 'Completed' AND Subject LIKE 'Day %'
            GROUP BY WhatId
        ]) {
            lastCommMap.put((Id) ar.get('wid'), (DateTime) ar.get('lastComm'));
        }

        // Load active manager for escalation
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
        List<Id> toEnrollDead = new List<Id>();
        Set<Id> toReactivateCancel = new Set<Id>();

        for (Intake__c i : intakes) {
            // Use last completed task date as "last communication".
            // Fall back to CreatedDate if no tasks completed yet.
            DateTime lastComm = lastCommMap.containsKey(i.Id) ? lastCommMap.get(i.Id) : i.CreatedDate;

            // Business hours elapsed since last communication
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

                // ── Becoming Dead ──────────────────────────────────
                // Auto-enroll in drip re-activation campaign.
                // Actual enroll call happens AFTER DML to avoid
                // any transaction ordering issues.
                if (newLevel == 'Dead') {
                    toEnrollDead.add(i.Id);
                }

                // ── Becoming Hot or Warm (re-engaged) ─────────────
                // Reset all cold/escalation flags so the cycle can
                // repeat if the lead goes cold again later.
                // Also cancel any active re-activation drip campaign.
                if ((newLevel == 'Hot' || newLevel == 'Warm') && (oldLevel == 'Dead' || oldLevel == 'Cold')) {
                    patch.Cold_Notified__c = false;
                    patch.Escalated_To_Manager__c = false;
                    dirty = true;
                    toReactivateCancel.add(i.Id);
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

        // ════════════════════════════════════════════════════════════
        // DRIP CAMPAIGN INTEGRATION — runs after DML
        // These are plain DML inserts inside DripCampaignService,
        // not callouts, so they are safe here.
        // ════════════════════════════════════════════════════════════

        // Auto-enroll each newly-Dead intake in the re-activation campaign.
        // The service guards against double-enrollment internally.
        for (Id intakeId : toEnrollDead) {
            DripCampaignService.autoEnrollDead(intakeId);
        }

        // Cancel any active re-activation drip for intakes that re-engaged.
        // Only cancels Type = Re-activation enrollments, not Deferred.
        if (!toReactivateCancel.isEmpty()) {
            DripCampaignService.cancelEnrollmentBatch(toReactivateCancel);
        }
    }

    // ════════════════════════════════════════════════════════════════
    // PRIVATE — EMAIL BUILDERS
    // ════════════════════════════════════════════════════════════════

    // ── Specialist "going cold" email ─────────────────────────────
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
            'Lead Going Cold — Action Required',
            'Hi ' + (specName ?? 'Specialist') + ',',
            'The following lead has had <strong>no contact for ' +
                bhDays.setScale(1) +
                ' business days</strong>. ' +
                'If you don\'t act soon this will be escalated to your manager.',
            new List<String[]>{
                new List<String>{ 'Intake', i.Name },
                new List<String>{ 'Client', client },
                new List<String>{ 'Incident Type', type },
                new List<String>{ 'BH Days Inactive', bhDays.setScale(1) + ' days' }
            },
            i.Id
        );

        Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
        em.setToAddresses(new List<String>{ toEmail });
        em.setSubject('Lead Going Cold — ' + i.Name + ' · ' + client);
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
            'Lead Escalated — Cold for ' + bhDaysCold.setScale(1) + ' BH Days',
            'Hi ' + mgrName + ',',
            'The following lead has been <strong>cold for ' +
                bhDaysCold.setScale(1) +
                ' business days</strong> ' +
                'without contact from the assigned specialist. ' +
                'It has been <strong>reassigned to you</strong>.',
            new List<String[]>{
                new List<String>{ 'Intake', i.Name },
                new List<String>{ 'Client', client },
                new List<String>{ 'Incident Type', type },
                new List<String>{ 'Was Assigned To', specName },
                new List<String>{ 'Total BH Days Idle', bhDaysTotal.setScale(1) + ' days' },
                new List<String>{ 'Days in Cold', bhDaysCold.setScale(1) + ' days' }
            },
            i.Id
        );

        Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
        em.setToAddresses(new List<String>{ toEmail });
        em.setSubject('Escalated — ' + i.Name + ' · ' + client + ' (' + bhDaysCold.setScale(1) + ' BH days cold)');
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
