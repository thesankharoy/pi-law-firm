public without sharing class DripCampaignService {
    // ════════════════════════════════════════════════════════════
    // CAMPAIGN ACTIVATION
    // Deferred: any number of campaigns may be active simultaneously.
    //           Specialist picks one explicitly when deferring a intake.
    // Re-activation: only ONE campaign may be active at a time.
    //           Activating one auto-deactivates every other active
    //           Re-activation campaign. This is what makes the
    //           automatic Dead-intake enrollment deterministic — there
    //           is no human in that loop to choose.
    // ════════════════════════════════════════════════════════════

    public static void setCampaignActive(Id campaignId, Boolean isActive) {
        DripCampaign__c c = [SELECT Id, Type__c FROM DripCampaign__c WHERE Id = :campaignId LIMIT 1];

        List<DripCampaign__c> toUpdate = new List<DripCampaign__c>();

        if (isActive && c.Type__c == 'Re-activation') {
            // Exclusivity ONLY applies to Re-activation. Deferred is untouched.
            for (DripCampaign__c other : [
                SELECT Id
                FROM DripCampaign__c
                WHERE Type__c = 'Re-activation' AND Id != :campaignId AND Active__c = TRUE
            ]) {
                other.Active__c = false;
                toUpdate.add(other);
            }
        }

        toUpdate.add(new DripCampaign__c(Id = campaignId, Active__c = isActive));
        update toUpdate;
    }

    // ════════════════════════════════════════════════════════════
    // CAMPAIGN LISTING — used by intakeDripStatus selection UI
    // ════════════════════════════════════════════════════════════

    // Returns ALL active campaigns of a given type with steps embedded,
    // so the LWC can render a selectable list with inline previews.
    public static List<Map<String, Object>> getActiveCampaigns(String type) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();

        List<DripCampaign__c> campaigns = [
            SELECT Id, Name, Description__c, Total_Duration_Days__c
            FROM DripCampaign__c
            WHERE Type__c = :type AND Active__c = TRUE
            ORDER BY Name ASC
        ];
        if (campaigns.isEmpty())
            return result;

        Set<Id> campaignIds = new Map<Id, DripCampaign__c>(campaigns).keySet();
        Map<Id, List<DripStep__c>> stepsByCampaign = loadStepsByCampaign(campaignIds);

        for (DripCampaign__c c : campaigns) {
            List<Map<String, Object>> stepPreviews = new List<Map<String, Object>>();
            List<DripStep__c> steps = stepsByCampaign.get(c.Id);
            if (steps != null) {
                for (DripStep__c s : steps) {
                    stepPreviews.add(
                        new Map<String, Object>{
                            'dayNumber' => s.Day_Number__c,
                            'channel' => s.Channel__c,
                            'subject' => s.Subject__c,
                            'taskType' => s.Task_Type__c
                        }
                    );
                }
            }
            result.add(
                new Map<String, Object>{
                    'id' => c.Id,
                    'name' => c.Name,
                    'description' => c.Description__c,
                    'totalDays' => c.Total_Duration_Days__c,
                    'stepCount' => stepPreviews.size(),
                    'steps' => stepPreviews
                }
            );
        }
        return result;
    }

    // ════════════════════════════════════════════════════════════
    // ENROLLMENT ENTRY POINTS
    // ════════════════════════════════════════════════════════════

    // Specialist explicitly picks the campaign in the LWC.
    public static void deferIntake(Id intakeId, Id campaignId, String reactivateDateStr) {
        List<DripCampaign__c> campaigns = [
            SELECT Id
            FROM DripCampaign__c
            WHERE Id = :campaignId AND Type__c = 'Deferred' AND Active__c = TRUE
            LIMIT 1
        ];
        if (campaigns.isEmpty()) {
            throw new AuraHandledException('The selected campaign is no longer active. Please choose another.');
        }

        Date reactivateAt;
        try {
            reactivateAt = Date.valueOf(reactivateDateStr);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid date.');
        }

        // Cancel any existing active enrollment first
        cancelEnrollmentForIntake(intakeId);

        // ── DML 1: update intake ───────────────────────────────────
        update new Intake__c(
            Id = intakeId,
            Status__c = 'Deferred',
            Deferred_Until__c = reactivateAt,
            Engagement_Level__c = 'Warm',
            Cold_Notified__c = false,
            Escalated_To_Manager__c = false
        );

        // ── DML 2: create enrollment ───────────────────────────────
        insert new DripEnrollment__c(
            Intake__c = intakeId,
            DripCampaign__c = campaignId,
            Type__c = 'Deferred',
            Status__c = 'Active',
            Enrolled_At__c = DateTime.now(),
            Reactivate_At__c = reactivateAt,
            Last_Step_Day__c = 0
        );
    }

    // Fully automatic — fired by IntakeEngagementService when level → Dead.
    // Exclusivity on Active__c (enforced in setCampaignActive) guarantees
    // at most one Re-activation campaign is active, so this query is
    // always deterministic with no extra flag needed.
    public static void autoEnrollDead(Id intakeId) {
        // Guard: already enrolled
        Integer existing = [
            SELECT COUNT()
            FROM DripEnrollment__c
            WHERE Intake__c = :intakeId AND Status__c = 'Active'
        ];
        if (existing > 0)
            return;

        List<DripCampaign__c> activeCampaigns = [
            SELECT Id
            FROM DripCampaign__c
            WHERE Type__c = 'Re-activation' AND Active__c = TRUE
            LIMIT 1
        ];
        if (activeCampaigns.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'No active Re-activation campaign — intake ' +
                    intakeId +
                    ' went Dead but was not auto-enrolled. ' +
                    'Activate a Re-activation campaign in Firm Settings → Drip Campaigns.'
            );
            return;
        }

        insert new DripEnrollment__c(
            Intake__c = intakeId,
            DripCampaign__c = activeCampaigns[0].Id,
            Type__c = 'Re-activation',
            Status__c = 'Active',
            Enrolled_At__c = DateTime.now(),
            Last_Step_Day__c = 0
        );
    }

    // ── Cancel any active enrollment for one intake ───────────────
    public static void cancelEnrollmentForIntake(Id intakeId) {
        List<DripEnrollment__c> active = [
            SELECT Id
            FROM DripEnrollment__c
            WHERE Intake__c = :intakeId AND Status__c = 'Active'
        ];
        for (DripEnrollment__c e : active)
            e.Status__c = 'Cancelled';
        if (!active.isEmpty())
            update active;
    }

    // ── Bulk cancel re-activation enrollments (on re-engagement) ──
    public static void cancelEnrollmentBatch(Set<Id> intakeIds) {
        List<DripEnrollment__c> active = [
            SELECT Id
            FROM DripEnrollment__c
            WHERE Intake__c IN :intakeIds AND Type__c = 'Re-activation' AND Status__c = 'Active'
        ];
        for (DripEnrollment__c e : active)
            e.Status__c = 'Cancelled';
        if (!active.isEmpty())
            update active;
    }

    // ── Get enrollment status for the LWC ────────────────────────
    public static Map<String, Object> getEnrollmentStatus(Id intakeId) {
        List<DripEnrollment__c> enrollments = [
            SELECT
                Id,
                Type__c,
                Status__c,
                Enrolled_At__c,
                Reactivate_At__c,
                Last_Step_Day__c,
                DripCampaign__r.Name,
                DripCampaign__r.Total_Duration_Days__c
            FROM DripEnrollment__c
            WHERE Intake__c = :intakeId AND Status__c = 'Active'
            ORDER BY Enrolled_At__c DESC
            LIMIT 1
        ];
        if (enrollments.isEmpty())
            return new Map<String, Object>{ 'isEnrolled' => false };

        DripEnrollment__c e = enrollments[0];
        Map<String, Object> result = new Map<String, Object>{
            'isEnrolled' => true,
            'enrollmentId' => e.Id,
            'type' => e.Type__c,
            'campaignName' => e.DripCampaign__r?.Name,
            'enrolledAt' => e.Enrolled_At__c != null ? e.Enrolled_At__c.format('MMM d, yyyy') : null,
            'lastStepDay' => e.Last_Step_Day__c,
            'totalDays' => e.DripCampaign__r?.Total_Duration_Days__c
        };

        if (e.Type__c == 'Deferred' && e.Reactivate_At__c != null) {
            result.put(
                'reactivateLabel',
                DateTime.newInstance(e.Reactivate_At__c, Time.newInstance(0, 0, 0, 0)).format('MMM d, yyyy')
            );
            result.put('daysLeft', (Integer) Date.today().daysBetween(e.Reactivate_At__c));
        }

        if (e.Type__c == 'Re-activation' && e.DripCampaign__r?.Total_Duration_Days__c != null) {
            Integer daysElapsed = e.Enrolled_At__c != null
                ? (Integer) e.Enrolled_At__c.date().daysBetween(Date.today())
                : 0;
            Decimal total = e.DripCampaign__r.Total_Duration_Days__c;
            result.put('daysElapsed', daysElapsed);
            result.put('progressPct', (Integer) Math.min(100, (daysElapsed / total) * 100));
        }

        return result;
    }

    // ════════════════════════════════════════════════════════════
    // DAILY SCHEDULER ENTRY POINT
    // ════════════════════════════════════════════════════════════

    public static void processEnrollments() {
        processDeferred();
        processReactivation();
    }

    // ── Deferred wake-ups — each enrollment already knows the EXACT
    // campaign the specialist chose at defer time, so this correctly
    // runs the right steps even when several Deferred campaigns are
    // active simultaneously. ──
    private static void processDeferred() {
        List<DripEnrollment__c> wakeUps = [
            SELECT Id, Intake__c, DripCampaign__c
            FROM DripEnrollment__c
            WHERE Type__c = 'Deferred' AND Status__c = 'Active' AND Reactivate_At__c <= :Date.today()
        ];
        if (wakeUps.isEmpty())
            return;

        Set<Id> intakeIds = new Set<Id>();
        Set<Id> campaignIds = new Set<Id>();
        for (DripEnrollment__c e : wakeUps) {
            intakeIds.add(e.Intake__c);
            campaignIds.add(e.DripCampaign__c);
        }

        Map<Id, Intake__c> intakeMap = new Map<Id, Intake__c>(
            [
                SELECT Id, Name, OwnerId, Incident_Type__c, Client__c, Client__r.Name, Client__r.Email
                FROM Intake__c
                WHERE Id IN :intakeIds
            ]
        );

        Map<Id, List<DripStep__c>> stepsByCampaign = loadStepsByCampaign(campaignIds);
        Map<Id, User> specialists = loadSpecialists(intakeMap.values());

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Task> tasks = new List<Task>();
        List<Intake__c> intUpd = new List<Intake__c>();
        List<DripEnrollment__c> enrollUpd = new List<DripEnrollment__c>();

        for (DripEnrollment__c e : wakeUps) {
            Intake__c i = intakeMap.get(e.Intake__c);
            if (i == null)
                continue;
            User specialist = specialists.get(i.OwnerId);

            List<DripStep__c> steps = stepsByCampaign.get(e.DripCampaign__c);
            if (steps != null && !steps.isEmpty()) {
                executeSteps(steps, i, specialist, emails, tasks);
            } else if (specialist != null) {
                // Safety net only — chosen campaign had zero steps configured
                tasks.add(
                    new Task(
                        Subject = 'Re-engage deferred intake — ' + i.Name,
                        WhatId = i.Id,
                        OwnerId = specialist.Id,
                        Status = 'Not Started',
                        Type = 'Call',
                        ActivityDate = Date.today(),
                        Description = 'Deferred intake is ready for follow-up. ' +
                            '(Chosen campaign had no steps configured.)'
                    )
                );
            }

            // Reset intake back into normal flow
            intUpd.add(
                new Intake__c(
                    Id = i.Id,
                    Status__c = 'Assigned',
                    Engagement_Level__c = 'Hot',
                    Deferred_Until__c = null,
                    Cold_Notified__c = false,
                    Escalated_To_Manager__c = false
                )
            );

            // Complete the enrollment
            e.Status__c = 'Completed';
            enrollUpd.add(e);
        }

        sendEmailsSafely(emails);
        if (!tasks.isEmpty())
            insert tasks;
        if (!intUpd.isEmpty())
            update intUpd;
        if (!enrollUpd.isEmpty())
            update enrollUpd;
    }

    // ── Re-activation step execution ──
    // MODIFIED: when a campaign completes (daysElapsed >= totalDays)
    // with zero client response, the intake is now automatically
    // turned down, the reason field is populated, and the intake
    // manager is notified by email and in-app bell. Previously the
    // enrollment simply flipped to Completed and the intake went
    // permanently silent with no further signal anywhere.
    private static void processReactivation() {
        Date today = Date.today();

        List<DripEnrollment__c> active = [
            SELECT
                Id,
                Intake__c,
                DripCampaign__c,
                Enrolled_At__c,
                Last_Step_Day__c,
                DripCampaign__r.Total_Duration_Days__c
            FROM DripEnrollment__c
            WHERE Type__c = 'Re-activation' AND Status__c = 'Active'
        ];
        if (active.isEmpty())
            return;

        Set<Id> campaignIds = new Set<Id>();
        Set<Id> intakeIds = new Set<Id>();
        Map<Id, Integer> daysElapsedMap = new Map<Id, Integer>();

        for (DripEnrollment__c e : active) {
            campaignIds.add(e.DripCampaign__c);
            intakeIds.add(e.Intake__c);
            Integer days = e.Enrolled_At__c != null ? (Integer) e.Enrolled_At__c.date().daysBetween(today) : 0;
            daysElapsedMap.put(e.Id, days);
        }

        Map<Id, List<DripStep__c>> stepsByCampaign = loadStepsByCampaign(campaignIds);

        // Last_Client_Response_At__c added — this is the field the
        // "use Client_Responded__c" requirement flows through. It is
        // populated exclusively by IntakeEngagementService.
        // handleClientResponseUpdate(), which only ever fires when a
        // specialist checks Client_Responded__c = true on a completed
        // Task. Checking this field here is equivalent to checking
        // Client_Responded__c directly, without needing a second Task
        // query.
        Map<Id, Intake__c> intakeMap = new Map<Id, Intake__c>(
            [
                SELECT
                    Id,
                    Name,
                    OwnerId,
                    Incident_Type__c,
                    Client__c,
                    Client__r.Name,
                    Client__r.Email,
                    Last_Client_Response_At__c
                FROM Intake__c
                WHERE Id IN :intakeIds
            ]
        );

        Map<Id, User> specialists = loadSpecialists(intakeMap.values());

        // Manager lookup — used only when a campaign completes with no
        // response, to notify whoever should pick this up next.
        List<Intake_Manager__c> mgrs = [
            SELECT User__c, User__r.Name, User__r.Email
            FROM Intake_Manager__c
            WHERE Active__c = TRUE
            LIMIT 1
        ];
        Id managerId = mgrs.isEmpty() ? null : mgrs[0].User__c;
        String managerName = mgrs.isEmpty() ? 'Manager' : mgrs[0].User__r.Name;
        String managerEmail = mgrs.isEmpty() ? null : mgrs[0].User__r.Email;

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Task> tasks = new List<Task>();
        List<DripEnrollment__c> enrollUpd = new List<DripEnrollment__c>();
        List<Intake__c> intakeUpd = new List<Intake__c>();
        List<Id> notifyManagerIntakeIds = new List<Id>();

        for (DripEnrollment__c e : active) {
            Integer daysElapsed = daysElapsedMap.get(e.Id);
            Integer lastStepDay = (Integer) (e.Last_Step_Day__c ?? 0);
            Integer totalDays = (Integer) (e.DripCampaign__r?.Total_Duration_Days__c ?? 90);
            List<DripStep__c> allSteps = stepsByCampaign.get(e.DripCampaign__c);
            Intake__c intake = intakeMap.get(e.Intake__c);
            User specialist = intake != null ? specialists.get(intake.OwnerId) : null;

            Integer maxStepDay = lastStepDay;

            if (allSteps != null && !allSteps.isEmpty() && intake != null) {
                List<DripStep__c> dueSteps = new List<DripStep__c>();
                for (DripStep__c step : allSteps) {
                    Integer stepDay = (Integer) step.Day_Number__c;
                    if (stepDay > daysElapsed)
                        break;
                    if (stepDay <= lastStepDay)
                        continue;
                    dueSteps.add(step);
                    if (stepDay > maxStepDay)
                        maxStepDay = stepDay;
                }
                if (!dueSteps.isEmpty())
                    executeSteps(dueSteps, intake, specialist, emails, tasks);
            }

            DripEnrollment__c patch = new DripEnrollment__c(Id = e.Id);
            if (maxStepDay > lastStepDay)
                patch.Last_Step_Day__c = maxStepDay;

            if (daysElapsed >= totalDays) {
                patch.Status__c = 'Completed';

                // ── Campaign exhausted — check for a genuine client
                // response before turning down. A real response during
                // the campaign window would already have cancelled this
                // enrollment via cancelEnrollmentBatch (called from
                // IntakeEngagementService.handleClientResponseUpdate),
                // removing it from this query entirely — so in the
                // normal case this branch only runs for intakes that
                // truly never responded. The explicit check here is a
                // defensive second guard against that same signal.
                Boolean respondedDuringCampaign =
                    intake != null &&
                    intake.Last_Client_Response_At__c != null &&
                    intake.Last_Client_Response_At__c >= e.Enrolled_At__c;

                if (intake != null && !respondedDuringCampaign) {
                    intakeUpd.add(
                        new Intake__c(
                            Id = intake.Id,
                            Status__c = 'Turned Down',
                            Turned_Down_Reason__c = 'Automatically turned down — completed the ' +
                                totalDays +
                                '-day re-activation drip campaign with zero ' +
                                'client response after going Dead.'
                        )
                    );
                    notifyManagerIntakeIds.add(intake.Id);
                }
            }

            enrollUpd.add(patch);
        }

        sendEmailsSafely(emails);
        if (!tasks.isEmpty())
            insert tasks;
        if (!enrollUpd.isEmpty())
            update enrollUpd;
        if (!intakeUpd.isEmpty())
            update intakeUpd;

        // Notification is plain DML/Messaging — not a callout — safe to fire after the DML above.
        if (!notifyManagerIntakeIds.isEmpty() && managerId != null) {
            notifyManagerCampaignExhausted(notifyManagerIntakeIds, intakeMap, managerId, managerName, managerEmail);
        }
    }

    // ── Shared step execution — used by both Deferred and Re-activation ──
    private static void executeSteps(
        List<DripStep__c> steps,
        Intake__c intake,
        User specialist,
        List<Messaging.SingleEmailMessage> emails,
        List<Task> tasks
    ) {
        for (DripStep__c step : steps) {
            if (step.Channel__c == 'Email') {
                String clientEmail = intake.Client__r?.Email;
                if (String.isNotBlank(clientEmail)) {
                    String body = mergeBody(step.Body__c, intake, specialist);
                    String subject = mergeBody(step.Subject__c, intake, specialist);
                    Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
                    em.setToAddresses(new List<String>{ clientEmail });
                    em.setSubject(subject);
                    em.setHtmlBody(buildEmailHtml(body, intake.Name));
                    em.setSaveAsActivity(false);
                    emails.add(em);
                }
            } else if (step.Channel__c == 'Specialist Task' && specialist != null) {
                tasks.add(
                    new Task(
                        Subject = mergeBody(step.Subject__c, intake, specialist),
                        WhatId = intake.Id,
                        OwnerId = specialist.Id,
                        Status = 'Not Started',
                        Type = String.isNotBlank(step.Task_Type__c) ? step.Task_Type__c : 'Call',
                        ActivityDate = Date.today(),
                        Description = mergeBody(step.Body__c, intake, specialist)
                    )
                );
            }
        }
    }

    // ── NEW — manager notification when a Re-activation campaign
    // exhausts with zero client response. Sends both an email and an
    // in-app bell notification, consistent with the escalation pattern
    // already used in IntakeEngagementService. ──
    private static void notifyManagerCampaignExhausted(
        List<Id> intakeIds,
        Map<Id, Intake__c> intakeMap,
        Id managerId,
        String managerName,
        String managerEmail
    ) {
        List<Messaging.SingleEmailMessage> mgrEmails = new List<Messaging.SingleEmailMessage>();

        List<CustomNotificationType> notifTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = 'Intake_Assignment'
            LIMIT 1
        ];
        Id notifTypeId = notifTypes.isEmpty() ? null : notifTypes[0].Id;

        for (Id intakeId : intakeIds) {
            Intake__c intake = intakeMap.get(intakeId);
            if (intake == null)
                continue;

            if (String.isNotBlank(managerEmail)) {
                mgrEmails.add(buildCampaignExhaustedEmail(intake, managerEmail, managerName));
            }

            if (notifTypeId != null) {
                try {
                    Messaging.CustomNotification notif = new Messaging.CustomNotification();
                    notif.setNotificationTypeId(notifTypeId);
                    notif.setTargetId(intakeId);
                    notif.setTitle('Re-activation exhausted — ' + intake.Name);
                    notif.setBody(
                        (intake.Client__r?.Name ?? 'Client') + ' never responded. Automatically turned down.'
                    );
                    notif.send(new Set<String>{ String.valueOf(managerId) });
                } catch (Exception ex) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'Campaign-exhausted notification failed [' + intakeId + ']: ' + ex.getMessage()
                    );
                }
            }
        }

        sendEmailsSafely(mgrEmails);
    }

    // ── NEW — manager email for exhausted-campaign turn-down ──
    private static Messaging.SingleEmailMessage buildCampaignExhaustedEmail(
        Intake__c intake,
        String toEmail,
        String managerName
    ) {
        String client = intake.Client__r?.Name ?? '—';
        String type = intake.Incident_Type__c ?? '—';

        String html =
            '<!DOCTYPE html><html><body>' +
            '<div style="font-family:Helvetica Neue,Helvetica,Arial,sans-serif;' +
            'max-width:620px;margin:0 auto;border:1px solid #e0e5ee;border-radius:8px;overflow:hidden;">' +
            '<div style="background:#04152f;padding:20px 28px;">' +
            '<p style="color:#fff;font-size:18px;font-weight:700;margin:0;">Delipat Law Group</p>' +
            '<p style="color:#a8bfd6;font-size:11px;margin:4px 0 0;text-transform:uppercase;' +
            'letter-spacing:0.08em;">Case Management Platform</p>' +
            '</div>' +
            '<div style="background:#fef2f2;border-left:4px solid #dc2626;padding:14px 20px;">' +
            '<p style="color:#dc2626;font-weight:700;margin:0;font-size:15px;">' +
            'Re-activation Campaign Exhausted — Turned Down</p></div>' +
            '<div style="padding:28px;background:#fff;">' +
            '<p style="color:#333;font-size:14px;margin:0 0 12px;">Hi ' +
            managerName +
            ',</p>' +
            '<p style="color:#333;font-size:14px;margin:0 0 20px;">' +
            'The following intake completed its full re-activation drip campaign with ' +
            '<strong>zero client response</strong>. It has been automatically marked ' +
            '<strong>Turned Down</strong>.</p>' +
            '<table style="width:100%;border-collapse:collapse;font-size:13px;margin-bottom:24px;">' +
            '<tr><td style="padding:10px 14px;background:#f4f6f9;color:#777;font-size:11px;' +
            'text-transform:uppercase;letter-spacing:0.05em;width:38%;">Intake</td>' +
            '<td style="padding:10px 14px;font-weight:600;color:#04152f;">' +
            intake.Name +
            '</td></tr>' +
            '<tr><td style="padding:10px 14px;background:#f4f6f9;color:#777;font-size:11px;' +
            'text-transform:uppercase;letter-spacing:0.05em;">Client</td>' +
            '<td style="padding:10px 14px;font-weight:600;color:#04152f;">' +
            client +
            '</td></tr>' +
            '<tr><td style="padding:10px 14px;background:#f4f6f9;color:#777;font-size:11px;' +
            'text-transform:uppercase;letter-spacing:0.05em;">Incident Type</td>' +
            '<td style="padding:10px 14px;font-weight:600;color:#04152f;">' +
            type +
            '</td></tr>' +
            '</table>' +
            '<div style="text-align:center;">' +
            '<a href="' +
            URL.getOrgDomainUrl().toExternalForm() +
            '/' +
            intake.Id +
            '" ' +
            'style="display:inline-block;background:#04152f;color:#fff;text-decoration:none;' +
            'padding:14px 32px;border-radius:8px;font-size:14px;font-weight:700;">View Intake Record →</a>' +
            '</div></div>' +
            '<div style="padding:16px 28px;background:#f8f9fb;border-top:1px solid #e0e5ee;">' +
            '<p style="color:#aaa;font-size:11px;margin:0;">' +
            'Delipat PI Platform · Automated Notification · Do not reply</p>' +
            '</div></div></body></html>';

        Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
        em.setToAddresses(new List<String>{ toEmail });
        em.setSubject('Turned Down — ' + intake.Name + ' · ' + client + ' (re-activation exhausted, no response)');
        em.setHtmlBody(html);
        em.setSaveAsActivity(false);
        return em;
    }

    // ── Private helpers ───────────────────────────────────────────
    private static Map<Id, List<DripStep__c>> loadStepsByCampaign(Set<Id> campaignIds) {
        Map<Id, List<DripStep__c>> result = new Map<Id, List<DripStep__c>>();
        for (DripStep__c s : [
            SELECT Id, DripCampaign__c, Day_Number__c, Channel__c, Subject__c, Body__c, Task_Type__c, Sort_Order__c
            FROM DripStep__c
            WHERE DripCampaign__c IN :campaignIds
            ORDER BY Day_Number__c ASC, Sort_Order__c ASC
        ]) {
            if (!result.containsKey(s.DripCampaign__c))
                result.put(s.DripCampaign__c, new List<DripStep__c>());
            result.get(s.DripCampaign__c).add(s);
        }
        return result;
    }

    private static Map<Id, User> loadSpecialists(List<Intake__c> intakes) {
        Set<Id> ownerIds = new Set<Id>();
        for (Intake__c i : intakes) {
            if (String.valueOf(i.OwnerId).startsWith('005'))
                ownerIds.add(i.OwnerId);
        }
        return ownerIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :ownerIds]);
    }

    private static void sendEmailsSafely(List<Messaging.SingleEmailMessage> emails) {
        if (emails.isEmpty())
            return;
        try {
            Messaging.sendEmail(emails);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Drip email failed: ' + ex.getMessage());
        }
    }

    private static String mergeBody(String template, Intake__c intake, User specialist) {
        if (String.isBlank(template))
            return '';
        String result = template;
        String clientFirst = intake.Client__r?.Name?.split(' ')[0] ?? 'there';
        String clientFull = intake.Client__r?.Name ?? '';
        String specName = specialist?.Name ?? 'our team';
        result = result.replace('{ClientFirstName}', clientFirst);
        result = result.replace('{ClientFullName}', clientFull);
        result = result.replace('{IntakeName}', intake.Name);
        result = result.replace('{SpecialistName}', specName);
        result = result.replace(
            '{IncidentType}',
            String.isNotBlank(intake.Incident_Type__c) ? intake.Incident_Type__c : 'your case'
        );
        return result;
    }

    private static String buildEmailHtml(String body, String intakeName) {
        String htmlBody = body.replace('\n', '<br/>');
        return '<!DOCTYPE html><html><body>' +
            '<div style="font-family:Helvetica Neue,Helvetica,Arial,sans-serif;' +
            'max-width:600px;margin:0 auto;border:1px solid #e0e5ee;border-radius:8px;overflow:hidden;">' +
            '<div style="background:#04152f;padding:20px 28px;">' +
            '<p style="color:#fff;font-size:18px;font-weight:700;margin:0;">Delipat Law Group</p></div>' +
            '<div style="padding:28px;background:#fff;">' +
            '<p style="color:#333;font-size:14px;line-height:1.8;margin:0;">' +
            htmlBody +
            '</p></div>' +
            '<div style="padding:16px 28px;background:#f8f9fb;border-top:1px solid #e0e5ee;">' +
            '<p style="color:#aaa;font-size:11px;margin:0;">Delipat PI Platform · ' +
            intakeName +
            ' · Do not reply</p>' +
            '</div></div></body></html>';
    }
}