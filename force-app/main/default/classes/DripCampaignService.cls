public without sharing class DripCampaignService {
    // ════════════════════════════════════════════════════════════
    // ENROLLMENT ENTRY POINTS
    // ════════════════════════════════════════════════════════════

    // ── Called from IntakeTrigger when Status → Deferred ─────────
    public static void enrollDeferredBatch(List<Intake__c> intakes) {
        DripCampaign__c campaign = findActiveCampaign('Deferred');
        if (campaign == null)
            return;

        Set<Id> intakeIds = new Map<Id, Intake__c>(intakes).keySet();

        // Guard: don't double-enroll
        Set<Id> alreadyEnrolled = new Set<Id>();
        for (DripEnrollment__c e : [
            SELECT Intake__c
            FROM DripEnrollment__c
            WHERE Intake__c IN :intakeIds AND Status__c = 'Active'
        ])
            alreadyEnrolled.add(e.Intake__c);

        List<DripEnrollment__c> toInsert = new List<DripEnrollment__c>();
        for (Intake__c i : intakes) {
            if (alreadyEnrolled.contains(i.Id))
                continue;
            Date reactivateAt = i.Deferred_Until__c != null ? i.Deferred_Until__c : Date.today().addDays(42);
            toInsert.add(
                new DripEnrollment__c(
                    Intake__c = i.Id,
                    DripCampaign__c = campaign.Id,
                    Type__c = 'Deferred',
                    Status__c = 'Active',
                    Enrolled_At__c = DateTime.now(),
                    Reactivate_At__c = reactivateAt,
                    Last_Step_Day__c = 0
                )
            );
        }
        if (!toInsert.isEmpty())
            insert toInsert;
    }

    // ── Called from LWC Defer modal ───────────────────────────────
    // Sets Status = Deferred, Deferred_Until__c, creates enrollment.
    // No callouts — all DML.
    public static void deferIntake(Id intakeId, String reactivateDateStr) {
        DripCampaign__c campaign = findActiveCampaign('Deferred');
        if (campaign == null) {
            throw new AuraHandledException(
                'No active Deferred campaign found. ' + 'Create one in Firm Settings → Drip Campaigns first.'
            );
        }

        Date reactivateAt;
        try {
            reactivateAt = Date.valueOf(reactivateDateStr);
        } catch (Exception e) {
            reactivateAt = Date.today().addDays(42);
        }

        // Cancel any existing active enrollment first
        cancelEnrollmentForIntake(intakeId);

        // ── DML 1: update intake ───────────────────────────────────
        update new Intake__c(
            Id = intakeId,
            Status__c = 'Deferred',
            Deferred_Until__c = reactivateAt,
            Engagement_Level__c = 'Warm', // suppresses cold/dead engine
            Cold_Notified__c = false,
            Escalated_To_Manager__c = false
        );

        // ── DML 2: create enrollment ───────────────────────────────
        insert new DripEnrollment__c(
            Intake__c = intakeId,
            DripCampaign__c = campaign.Id,
            Type__c = 'Deferred',
            Status__c = 'Active',
            Enrolled_At__c = DateTime.now(),
            Reactivate_At__c = reactivateAt,
            Last_Step_Day__c = 0
        );
    }

    // ── Called from IntakeEngagementService when level → Dead ─────
    public static void autoEnrollDead(Id intakeId) {
        // Guard: already enrolled
        Integer existing = [
            SELECT COUNT()
            FROM DripEnrollment__c
            WHERE Intake__c = :intakeId AND Status__c = 'Active'
        ];
        if (existing > 0)
            return;

        DripCampaign__c campaign = findActiveCampaign('Re-activation');
        if (campaign == null)
            return;

        insert new DripEnrollment__c(
            Intake__c = intakeId,
            DripCampaign__c = campaign.Id,
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
        if (enrollments.isEmpty()) {
            return new Map<String, Object>{ 'isEnrolled' => false };
        }

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

    // ════════════════════════════════════════════════════════════
    // PRIVATE — DEFERRED WAKE-UPS
    // ════════════════════════════════════════════════════════════

    private static void processDeferred() {
        List<DripEnrollment__c> wakeUps = [
            SELECT Id, Intake__c, DripCampaign__r.Name
            FROM DripEnrollment__c
            WHERE Type__c = 'Deferred' AND Status__c = 'Active' AND Reactivate_At__c <= :Date.today()
        ];
        if (wakeUps.isEmpty())
            return;

        Set<Id> intakeIds = new Set<Id>();
        for (DripEnrollment__c e : wakeUps)
            intakeIds.add(e.Intake__c);

        Map<Id, Intake__c> intakeMap = new Map<Id, Intake__c>(
            [
                SELECT Id, Name, OwnerId, Incident_Type__c, Client__c, Client__r.Name, Client__r.Email
                FROM Intake__c
                WHERE Id IN :intakeIds
            ]
        );

        Set<Id> ownerIds = new Set<Id>();
        for (Intake__c i : intakeMap.values()) {
            if (String.valueOf(i.OwnerId).startsWith('005'))
                ownerIds.add(i.OwnerId);
        }
        Map<Id, User> specialists = ownerIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :ownerIds]);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Task> tasks = new List<Task>();
        List<Intake__c> intUpd = new List<Intake__c>();
        List<DripEnrollment__c> enrollUpd = new List<DripEnrollment__c>();

        for (DripEnrollment__c e : wakeUps) {
            Intake__c i = intakeMap.get(e.Intake__c);
            if (i == null)
                continue;
            User specialist = specialists.get(i.OwnerId);

            // Re-engagement email to client
            if (String.isNotBlank(i.Client__r?.Email)) {
                String firstName = i.Client__r.Name?.split(' ')[0] ?? 'there';
                String caseType = String.isNotBlank(i.Incident_Type__c) ? i.Incident_Type__c : 'your case';
                String body =
                    'Hi ' +
                    firstName +
                    ',\n\n' +
                    'As requested, we\'re following up regarding ' +
                    caseType +
                    '. ' +
                    'Our team is ready to assist and we look forward to connecting with you.\n\n' +
                    'Please don\'t hesitate to reach out — we\'re here for you.\n\n' +
                    (specialist != null ? specialist.Name : 'The intake team');

                Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
                em.setToAddresses(new List<String>{ i.Client__r.Email });
                em.setSubject('Following up on your case — ' + i.Name);
                em.setHtmlBody(buildEmailHtml(body, i.Name));
                em.setSaveAsActivity(false);
                emails.add(em);
            }

            // Task for specialist
            if (specialist != null) {
                tasks.add(
                    new Task(
                        Subject = 'Re-engage deferred lead — ' + i.Name,
                        WhatId = i.Id,
                        OwnerId = specialist.Id,
                        Status = 'Not Started',
                        Type = 'Call',
                        ActivityDate = Date.today(),
                        Description = 'This lead was deferred and is now ready for follow-up.'
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

        // Emails are NOT callouts — safe after queries, before or after DML
        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Drip deferred email failed: ' + ex.getMessage());
            }
        }
        if (!tasks.isEmpty())
            insert tasks;
        if (!intUpd.isEmpty())
            update intUpd;
        if (!enrollUpd.isEmpty())
            update enrollUpd;
    }

    // ════════════════════════════════════════════════════════════
    // PRIVATE — RE-ACTIVATION STEP EXECUTION
    // ════════════════════════════════════════════════════════════

    private static void processReactivation() {
        Date today = Date.today();

        List<DripEnrollment__c> active = [
            SELECT
                Id,
                Intake__c,
                DripCampaign__c,
                Enrolled_At__c,
                Last_Step_Day__c,
                DripCampaign__r.Total_Duration_Days__c,
                DripCampaign__r.Name
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

        // Load all steps for relevant campaigns in one query
        Map<Id, List<DripStep__c>> stepsByCampaign = new Map<Id, List<DripStep__c>>();
        for (DripStep__c s : [
            SELECT Id, DripCampaign__c, Day_Number__c, Channel__c, Subject__c, Body__c, Task_Type__c, Sort_Order__c
            FROM DripStep__c
            WHERE DripCampaign__c IN :campaignIds
            ORDER BY Day_Number__c ASC, Sort_Order__c ASC
        ]) {
            if (!stepsByCampaign.containsKey(s.DripCampaign__c)) {
                stepsByCampaign.put(s.DripCampaign__c, new List<DripStep__c>());
            }
            stepsByCampaign.get(s.DripCampaign__c).add(s);
        }

        // Load intakes
        Map<Id, Intake__c> intakeMap = new Map<Id, Intake__c>(
            [
                SELECT Id, Name, OwnerId, Incident_Type__c, Client__c, Client__r.Name, Client__r.Email
                FROM Intake__c
                WHERE Id IN :intakeIds
            ]
        );

        Set<Id> ownerIds = new Set<Id>();
        for (Intake__c i : intakeMap.values()) {
            if (String.valueOf(i.OwnerId).startsWith('005'))
                ownerIds.add(i.OwnerId);
        }
        Map<Id, User> specialists = ownerIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :ownerIds]);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Task> tasks = new List<Task>();
        List<DripEnrollment__c> enrollUpd = new List<DripEnrollment__c>();

        for (DripEnrollment__c e : active) {
            Integer daysElapsed = daysElapsedMap.get(e.Id);
            Integer lastStepDay = (Integer) (e.Last_Step_Day__c ?? 0);
            Integer totalDays = (Integer) (e.DripCampaign__r?.Total_Duration_Days__c ?? 90);
            List<DripStep__c> steps = stepsByCampaign.get(e.DripCampaign__c);
            Intake__c intake = intakeMap.get(e.Intake__c);
            User specialist = intake != null ? specialists.get(intake.OwnerId) : null;

            Integer maxStepDay = lastStepDay;

            if (steps != null && !steps.isEmpty() && intake != null) {
                for (DripStep__c step : steps) {
                    Integer stepDay = (Integer) step.Day_Number__c;
                    if (stepDay > daysElapsed)
                        break; // not yet
                    if (stepDay <= lastStepDay)
                        continue; // already fired

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
                                ActivityDate = today,
                                Description = mergeBody(step.Body__c, intake, specialist)
                            )
                        );
                    }

                    if (stepDay > maxStepDay)
                        maxStepDay = stepDay;
                }
            }

            // Patch enrollment
            DripEnrollment__c patch = new DripEnrollment__c(Id = e.Id);
            if (maxStepDay > lastStepDay)
                patch.Last_Step_Day__c = maxStepDay;
            if (daysElapsed >= totalDays)
                patch.Status__c = 'Completed';
            enrollUpd.add(patch);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Drip re-activation email failed: ' + ex.getMessage());
            }
        }
        if (!tasks.isEmpty())
            insert tasks;
        if (!enrollUpd.isEmpty())
            update enrollUpd;
    }

    // ════════════════════════════════════════════════════════════
    // PRIVATE HELPERS
    // ════════════════════════════════════════════════════════════

    private static DripCampaign__c findActiveCampaign(String type) {
        List<DripCampaign__c> campaigns = [
            SELECT Id, Name, Total_Duration_Days__c
            FROM DripCampaign__c
            WHERE Type__c = :type AND Active__c = TRUE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return campaigns.isEmpty() ? null : campaigns[0];
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
            'max-width:600px;margin:0 auto;border:1px solid #e0e5ee;' +
            'border-radius:8px;overflow:hidden;">' +
            '<div style="background:#04152f;padding:20px 28px;">' +
            '<p style="color:#fff;font-size:18px;font-weight:700;margin:0;">' +
            'Delipat Law Group</p></div>' +
            '<div style="padding:28px;background:#fff;">' +
            '<p style="color:#333;font-size:14px;line-height:1.8;margin:0;">' +
            htmlBody +
            '</p></div>' +
            '<div style="padding:16px 28px;background:#f8f9fb;' +
            'border-top:1px solid #e0e5ee;">' +
            '<p style="color:#aaa;font-size:11px;margin:0;">' +
            'Delipat PI Platform · ' +
            intakeName +
            ' · Do not reply</p>' +
            '</div></div></body></html>';
    }
}