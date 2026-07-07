public without sharing class IntakeFollowUpService {
    // PREVIOUSLY a hardcoded constant — replaced with getSkipStatuses(),
    // Reads skip statuses from Follow_Up_Skip_Status__mdt.
    // skipStatusesCache so repeated calls within the same execution don't re-query.
    private static Set<String> skipStatusesCache;

    public static Set<String> getSkipStatuses() {
        if (skipStatusesCache != null)
            return skipStatusesCache;

        skipStatusesCache = new Set<String>();
        for (Follow_Up_Skip_Status__mdt s : [
            SELECT Status_Value__c
            FROM Follow_Up_Skip_Status__mdt
            WHERE Active__c = TRUE
        ]) {
            if (String.isNotBlank(s.Status_Value__c)) {
                skipStatusesCache.add(s.Status_Value__c);
            }
        }

        // Safety net — if the admin hasn't created any CMDT records yet,
        // fall back to the original hardcoded set rather than skipping
        // nothing at all.
        if (skipStatusesCache.isEmpty()) {
            skipStatusesCache = new Set<String>{
                'Retainer Agreement Signed',
                'Referred Out',
                'Turned Down',
                'Converted'
            };
        }

        return skipStatusesCache;
    }

    private static final List<String[]> TASK_DEFS = new List<String[]>{
        new List<String>{ 'Call', '📞 Call' },
        new List<String>{ 'Email', '✉️ Email' },
        new List<String>{ 'SMS', '💬 SMS' }
    };

    // ── ENTRY POINT 1: after insert ───────────────────────────────
    public static void scheduleTasks(List<Intake__c> intakes) {
        if (intakes == null || intakes.isEmpty())
            return;

        Set<String> skipStatuses = getSkipStatuses();

        // Separate user-owned from queue-owned
        // Queue-owned: Day 1 clock hasn't started — do NOTHING until a specialist claims it
        List<Intake__c> userOwned = new List<Intake__c>();
        for (Intake__c i : intakes) {
            if (skipStatuses.contains(i.Status__c))
                continue;
            if (i.OwnerId == null)
                continue;
            if (i.OwnerId.getSObjectType() == Schema.User.SObjectType)
                userOwned.add(i);
            // Queue-owned: intentionally skipped
        }
        if (userOwned.isEmpty())
            return;

        // Query for Client name — Trigger.new relationship fields are not populated
        // NOW also pulls Client__r.Phone / Client__r.MobilePhone / Client__r.Email —
        // needed for the channel-specific task description built in
        // buildDescription() below (Call/SMS use phone, Email uses email address).
        Set<Id> ids = new Map<Id, Intake__c>(userOwned).keySet();
        Map<Id, Intake__c> withClient = new Map<Id, Intake__c>(
            [
                SELECT
                    Id,
                    Client__c,
                    Client__r.Name,
                    Client__r.Phone,
                    Client__r.MobilePhone,
                    Client__r.Email,
                    OwnerId,
                    Status__c
                FROM Intake__c
                WHERE Id IN :ids
            ]
        );

        startDay1(withClient.values());
    }

    // ── ENTRY POINT 2: scheduler runs every morning ───────────────
    public static void createScheduledTasks() {
        Id bhId = defaultBHId();
        if (bhId != null && !BusinessHours.isWithin(bhId, System.now()))
            return;

        Set<String> skipStatuses = getSkipStatuses();

        // NOW also pulls Intake__r.Client__r.Phone / MobilePhone / Email —
        // needed for the channel-specific task description built at
        // processSchedules() time.
        List<Intake_Follow_Up__c> due = [
            SELECT
                Id,
                Intake__c,
                Day_Number__c,
                Assigned_To__c,
                Intake__r.Client__c,
                Intake__r.Client__r.Name,
                Intake__r.Client__r.Phone,
                Intake__r.Client__r.MobilePhone,
                Intake__r.Client__r.Email,
                Intake__r.Status__c
            FROM Intake_Follow_Up__c
            WHERE Scheduled_Date__c <= :Date.today() AND Created__c = FALSE AND Intake__r.Status__c NOT IN :skipStatuses
        ];
        if (!due.isEmpty())
            processSchedules(due);
    }

    // ── ENTRY POINT 3: after update — owner changed ───────────────
    public static void reassignTasks(List<Intake__c> newList, Map<Id, Intake__c> oldMap) {
        Map<Id, Id> changedToUser = new Map<Id, Id>(); // intakeId → new user Id
        Map<Id, Id> changedToQueue = new Map<Id, Id>(); // intakeId → new queue Id

        for (Intake__c i : newList) {
            Intake__c old = oldMap.get(i.Id);
            if (i.OwnerId == old.OwnerId || i.OwnerId == null)
                continue;
            if (i.OwnerId.getSObjectType() == Schema.User.SObjectType) {
                changedToUser.put(i.Id, i.OwnerId);
            } else {
                changedToQueue.put(i.Id, i.OwnerId);
            }
        }
        if (changedToUser.isEmpty() && changedToQueue.isEmpty())
            return;

        // ── User assignments ──────────────────────────────────────
        if (!changedToUser.isEmpty()) {
            // 1. Reassign existing open tasks (handles user → different user)
            List<Task> openTasks = [
                SELECT Id, WhatId
                FROM Task
                WHERE WhatId IN :changedToUser.keySet() AND Status = 'Not Started'
            ];
            for (Task t : openTasks)
                t.OwnerId = changedToUser.get(t.WhatId);
            if (!openTasks.isEmpty())
                update openTasks;

            // 2. Update Assigned_To__c on any existing pending schedules
            List<Intake_Follow_Up__c> pending = [
                SELECT Id, Intake__c
                FROM Intake_Follow_Up__c
                WHERE Intake__c IN :changedToUser.keySet() AND Created__c = FALSE
            ];
            for (Intake_Follow_Up__c s : pending) {
                s.Assigned_To__c = String.valueOf(changedToUser.get(s.Intake__c));
            }
            if (!pending.isEmpty())
                update pending;

            // 3. Detect queue → user transitions (no schedules exist = was queue-owned)
            //    Day 1 clock starts NOW for these intakes
            Set<Id> alreadyScheduled = new Set<Id>();
            for (Intake_Follow_Up__c s : [
                SELECT Intake__c
                FROM Intake_Follow_Up__c
                WHERE Intake__c IN :changedToUser.keySet()
            ])
                alreadyScheduled.add(s.Intake__c);

            Set<Id> needsDay1 = new Set<Id>();
            for (Id intakeId : changedToUser.keySet()) {
                if (!alreadyScheduled.contains(intakeId))
                    needsDay1.add(intakeId);
            }

            if (!needsDay1.isEmpty()) {
                // NOW also pulls Client__r.Phone / Client__r.MobilePhone /
                // Client__r.Email — same reason as scheduleTasks()'s
                // withClient query above.
                List<Intake__c> freshlyAssigned = [
                    SELECT
                        Id,
                        Client__c,
                        Client__r.Name,
                        Client__r.Phone,
                        Client__r.MobilePhone,
                        Client__r.Email,
                        OwnerId,
                        Status__c
                    FROM Intake__c
                    WHERE Id IN :needsDay1
                ];
                startDay1(freshlyAssigned);
            }

            // 4. Mid-day flush: existing Day 2/3 schedules that are already overdue
            //    (covers the case where a user→user transfer happened while Day 2 was past due)
            Id bhId = defaultBHId();
            if (bhId != null && BusinessHours.isWithin(bhId, System.now())) {
                Set<String> skipStatuses = getSkipStatuses();

                // NOW also pulls Intake__r.Client__r.Phone / MobilePhone / Email —
                // same reason as createScheduledTasks()'s due query above.
                List<Intake_Follow_Up__c> overdue = [
                    SELECT
                        Id,
                        Intake__c,
                        Day_Number__c,
                        Assigned_To__c,
                        Intake__r.Client__c,
                        Intake__r.Client__r.Name,
                        Intake__r.Client__r.Phone,
                        Intake__r.Client__r.MobilePhone,
                        Intake__r.Client__r.Email,
                        Intake__r.Status__c
                    FROM Intake_Follow_Up__c
                    WHERE
                        Intake__c IN :changedToUser.keySet()
                        AND Scheduled_Date__c <= :Date.today()
                        AND Created__c = FALSE
                        AND Intake__r.Status__c NOT IN :skipStatuses
                ];
                if (!overdue.isEmpty())
                    processSchedules(overdue);
            }
        }

        // ── Queue assignments — tasks stay with previous user, no new schedules ──
        // Pending schedules that haven't been created yet are left as-is;
        // they'll flush when the intake is claimed by a user again.
        // (No action needed for changedToQueue)
    }

    // ── Core: start the 3-day clock for user-owned intakes ────────
    private static void startDay1(List<Intake__c> intakes) {
        if (intakes == null || intakes.isEmpty())
            return;

        Id bhId = defaultBHId();
        if (bhId == null)
            return;

        Set<String> skipStatuses = getSkipStatuses();

        // Bulk-load specialist names once for the whole batch — needed for
        // the personalized "Hey {name}, ..." greeting in the Day 1 task
        // description built below. Avoids a query per record inside the loop.
        Set<Id> ownerIds = new Set<Id>();
        for (Intake__c intake : intakes) {
            if (intake.OwnerId != null && intake.OwnerId.getSObjectType() == Schema.User.SObjectType) {
                ownerIds.add(intake.OwnerId);
            }
        }
        Map<Id, User> specialistMap = ownerIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :ownerIds]);

        DateTime now = System.now();
        Boolean withinBH = BusinessHours.isWithin(bhId, now);

        List<Task> immediateTasks = new List<Task>();
        List<Intake_Follow_Up__c> schedules = new List<Intake_Follow_Up__c>();

        for (Intake__c intake : intakes) {
            if (skipStatuses.contains(intake.Status__c))
                continue;
            if (intake.OwnerId == null)
                continue;
            // Confirm still user-owned (could have changed between insert and drain)
            if (intake.OwnerId.getSObjectType() != Schema.User.SObjectType)
                continue;

            String ownerStr = String.valueOf(intake.OwnerId);
            String clientName = intake.Client__r?.Name;
            // Prefer MobilePhone over Phone — same convention already used
            // in ContactIntelligenceService, kept consistent across the platform.
            String clientPhone = pickPhone(intake.Client__r?.MobilePhone, intake.Client__r?.Phone);
            String clientEmail = intake.Client__r?.Email;
            String specialistName = specialistMap.containsKey(intake.OwnerId)
                ? specialistMap.get(intake.OwnerId).Name
                : null;

            // Day 1 = now (if BH) or next BH morning
            // Day 2 = next business morning after Day 1's date
            // Day 3 = next business morning after Day 2's date
            DateTime day1Start = withinBH ? now : nextBusinessDayStart(bhId, now);
            DateTime day2Start = nextBusinessDayStart(bhId, day1Start);
            DateTime day3Start = nextBusinessDayStart(bhId, day2Start);

            if (withinBH) {
                // Day 1: create tasks right now
                immediateTasks.addAll(
                    buildTasks(
                        intake.Id,
                        intake.Client__c,
                        clientName,
                        clientPhone,
                        clientEmail,
                        intake.OwnerId,
                        specialistName,
                        1,
                        Date.today()
                    )
                );
                // Day 2 & 3: defer to morning scheduler
                schedules.add(buildSchedule(intake.Id, 2, day2Start.date(), ownerStr));
                schedules.add(buildSchedule(intake.Id, 3, day3Start.date(), ownerStr));
            } else {
                // All 3 days scheduled — Day 1 goes to next BH morning
                schedules.add(buildSchedule(intake.Id, 1, day1Start.date(), ownerStr));
                schedules.add(buildSchedule(intake.Id, 2, day2Start.date(), ownerStr));
                schedules.add(buildSchedule(intake.Id, 3, day3Start.date(), ownerStr));
            }
        }

        if (!immediateTasks.isEmpty())
            insert immediateTasks;
        if (!schedules.isEmpty())
            insert schedules;
    }

    // ── Shared processor (morning scheduler + mid-day flush) ──────
    public static void processSchedules(List<Intake_Follow_Up__c> schedules) {
        try {
            // Bulk-load specialist names once for the whole batch — same
            // reason as startDay1() above. This is where Day 2/3 (and any
            // off-hours Day 1) tasks actually get their Description built,
            // so the lookup is needed here independently of startDay1()'s.
            Set<Id> ownerIds = new Set<Id>();
            for (Intake_Follow_Up__c s : schedules) {
                try {
                    Id oid = Id.valueOf(s.Assigned_To__c);
                    if (oid.getSObjectType() == Schema.User.SObjectType) {
                        ownerIds.add(oid);
                    }
                } catch (Exception e) {
                    continue;
                }
            }
            Map<Id, User> specialistMap = ownerIds.isEmpty()
                ? new Map<Id, User>()
                : new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :ownerIds]);

            List<Task> tasks = new List<Task>();
            List<Intake_Follow_Up__c> toMark = new List<Intake_Follow_Up__c>();

            for (Intake_Follow_Up__c s : schedules) {
                Id ownerId;
                try {
                    ownerId = Id.valueOf(s.Assigned_To__c);
                } catch (Exception e) {
                    continue;
                }

                // Hard guard: Tasks cannot be queue-owned — skip, do not mark as created
                // (will be picked up after specialist claims the intake)
                if (ownerId.getSObjectType() != Schema.User.SObjectType)
                    continue;

                Integer day = s.Day_Number__c != null ? (Integer) s.Day_Number__c : 1;
                String clientPhone = pickPhone(s.Intake__r?.Client__r?.MobilePhone, s.Intake__r?.Client__r?.Phone);
                String clientEmail = s.Intake__r?.Client__r?.Email;
                String specialistName = specialistMap.containsKey(ownerId) ? specialistMap.get(ownerId).Name : null;

                tasks.addAll(
                    buildTasks(
                        s.Intake__c,
                        s.Intake__r.Client__c,
                        s.Intake__r.Client__r?.Name,
                        clientPhone,
                        clientEmail,
                        ownerId,
                        specialistName,
                        day,
                        Date.today()
                    )
                );
                toMark.add(new Intake_Follow_Up__c(Id = s.Id, Created__c = true));
            }

            if (!tasks.isEmpty())
                insert tasks;
            if (!toMark.isEmpty())
                update toMark;
        } catch (Exception e) {
            Error_Log__c log = new Error_Log__c(Error_Label__c = e.getMessage(), Message__c = e.getStackTraceString());
            insert log;
        }
    }

    // ── Builders ──────────────────────────────────────────────────
    private static List<Task> buildTasks(
        Id intakeId,
        Id contactId,
        String contactName,
        String clientPhone,
        String clientEmail,
        Id ownerId,
        String specialistName,
        Integer day,
        Date actDate
    ) {
        String nameSuffix = String.isNotBlank(contactName) ? ' — ' + contactName : '';

        List<Task> tasks = new List<Task>();
        for (String[] def : TASK_DEFS) {
            // PREVIOUSLY one shared description was built ONCE per intake
            // and stamped identically onto all three channel tasks — which
            // is how a phone number ended up on the Email task description.
            // Now built PER CHANNEL, inside this loop, so each task
            // references the contact detail that channel actually uses.
            String description = buildDescription(specialistName, contactName, clientPhone, clientEmail, day, def[0]);

            tasks.add(
                new Task(
                    WhatId = intakeId,
                    WhoId = contactId,
                    OwnerId = ownerId,
                    Subject = 'Day ' + day + ' ' + def[1] + nameSuffix,
                    Type = def[0],
                    Status = 'Not Started',
                    Priority = 'Normal',
                    ActivityDate = actDate,
                    Description = description
                )
            );
        }
        return tasks;
    }

    // ── Personalized, CHANNEL-SPECIFIC task description ──────────────
    // PREVIOUSLY: one generic sentence shared across Call/Email/SMS,
    // always referencing the phone number — nonsensical on the Email
    // task ("please follow up... on +91..." makes no sense for an
    // email). Now branches on channelType so each task tells the
    // specialist to use the actual channel it represents, with the
    // matching contact detail: Call and SMS reference the phone number
    // (different verb: "call" vs "text"), Email references the client's
    // actual email address instead.
    private static String buildDescription(
        String specialistName,
        String contactName,
        String clientPhone,
        String clientEmail,
        Integer day,
        String channelType
    ) {
        String specialistFirst = String.isNotBlank(specialistName) ? specialistName.split(' ')[0] : 'there';
        String clientDisplay = String.isNotBlank(contactName) ? contactName : 'the client';
        String ordinalLabel = ordinal(day);
        String phoneDisplay = String.isNotBlank(clientPhone) ? clientPhone : 'the phone number on file';
        String emailDisplay = String.isNotBlank(clientEmail) ? clientEmail : 'the email address on file';

        if (channelType == 'Call') {
            return 'Hey ' +
                specialistFirst +
                ', please call ' +
                clientDisplay +
                ' at ' +
                phoneDisplay +
                ' by end of day today — this is the ' +
                ordinalLabel +
                ' follow-up call from your side.';
        }
        if (channelType == 'SMS') {
            return 'Hey ' +
                specialistFirst +
                ', please text ' +
                clientDisplay +
                ' at ' +
                phoneDisplay +
                ' by end of day today — this is the ' +
                ordinalLabel +
                ' follow-up text from your side.';
        }
        if (channelType == 'Email') {
            return 'Hey ' +
                specialistFirst +
                ', please email ' +
                clientDisplay +
                ' at ' +
                emailDisplay +
                ' by end of day today — this is the ' +
                ordinalLabel +
                ' follow-up email from your side.';
        }

        // Fallback for any unexpected channel type — generic, no contact
        // detail assumed since we don't know which one applies.
        return 'Hey ' +
            specialistFirst +
            ', please follow up with ' +
            clientDisplay +
            ' by end of day today — this is the ' +
            ordinalLabel +
            ' follow-up from your side.';
    }

    // ── Ordinal label for the follow-up day number (1 -> "1st", etc.) ──
    private static String ordinal(Integer n) {
        if (n == 1)
            return '1st';
        if (n == 2)
            return '2nd';
        if (n == 3)
            return '3rd';
        return n + 'th';
    }

    // ── Prefer MobilePhone over Phone — same convention already used in
    // ContactIntelligenceService, kept consistent across the platform. ──
    private static String pickPhone(String mobilePhone, String phone) {
        if (String.isNotBlank(mobilePhone))
            return mobilePhone;
        if (String.isNotBlank(phone))
            return phone;
        return null;
    }

    private static Intake_Follow_Up__c buildSchedule(Id intakeId, Integer day, Date schedDate, String ownerId) {
        return new Intake_Follow_Up__c(
            Intake__c = intakeId,
            Day_Number__c = day,
            Scheduled_Date__c = schedDate,
            Assigned_To__c = ownerId,
            Created__c = false
        );
    }

    // ── Business hours helpers ─────────────────────────────────────
    private static Id bhIdCache;
    private static Id defaultBHId() {
        if (bhIdCache != null)
            return bhIdCache;
        List<BusinessHours> bhs = [SELECT Id FROM BusinessHours WHERE IsDefault = TRUE LIMIT 1];
        bhIdCache = bhs.isEmpty() ? null : bhs[0].Id;
        return bhIdCache;
    }

    private static DateTime nextBusinessDayStart(Id bhId, DateTime fromDt) {
        // Midnight of next calendar day is always before BH open time,
        // forcing nextStartDate to return the genuine next BH morning.
        // Handles weekends and holidays automatically via the BH config.
        DateTime probe = DateTime.newInstance(fromDt.date().addDays(1), Time.newInstance(0, 0, 0, 0));
        return BusinessHours.nextStartDate(bhId, probe);
    }
}