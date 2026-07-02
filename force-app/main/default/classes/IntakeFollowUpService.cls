public without sharing class IntakeFollowUpService {
    // PREVIOUSLY a hardcoded constant — replaced with getSkipStatuses(),
    // Reads skip statuses from Follow_Up_Skip_Status__mdt.
    // skipStatusesCache so repeated calls within the same execution don't re-query.
    private static Set<String> skipStatusesCache;

    private static Set<String> getSkipStatuses() {
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
        Set<Id> ids = new Map<Id, Intake__c>(userOwned).keySet();
        Map<Id, Intake__c> withClient = new Map<Id, Intake__c>(
            [
                SELECT Id, Client__c, Client__r.Name, OwnerId, Status__c
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

        List<Intake_Follow_Up__c> due = [
            SELECT
                Id,
                Intake__c,
                Day_Number__c,
                Assigned_To__c,
                Intake__r.Client__c,
                Intake__r.Client__r.Name,
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
                List<Intake__c> freshlyAssigned = [
                    SELECT Id, Client__c, Client__r.Name, OwnerId, Status__c
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

                List<Intake_Follow_Up__c> overdue = [
                    SELECT
                        Id,
                        Intake__c,
                        Day_Number__c,
                        Assigned_To__c,
                        Intake__r.Client__c,
                        Intake__r.Client__r.Name,
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

            // Day 1 = now (if BH) or next BH morning
            // Day 2 = next business morning after Day 1's date
            // Day 3 = next business morning after Day 2's date
            DateTime day1Start = withinBH ? now : nextBusinessDayStart(bhId, now);
            DateTime day2Start = nextBusinessDayStart(bhId, day1Start);
            DateTime day3Start = nextBusinessDayStart(bhId, day2Start);

            if (withinBH) {
                // Day 1: create tasks right now
                immediateTasks.addAll(
                    buildTasks(intake.Id, intake.Client__c, clientName, intake.OwnerId, 1, Date.today())
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
                tasks.addAll(
                    buildTasks(
                        s.Intake__c,
                        s.Intake__r.Client__c,
                        s.Intake__r.Client__r?.Name,
                        ownerId,
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
        Id ownerId,
        Integer day,
        Date actDate
    ) {
        String nameSuffix = String.isNotBlank(contactName) ? ' — ' + contactName : '';
        List<Task> tasks = new List<Task>();
        for (String[] def : TASK_DEFS) {
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
                    Description = 'Day ' +
                        day +
                        ' automated follow-up. Complete this ' +
                        def[0].toLowerCase() +
                        ' before end of business today.'
                )
            );
        }
        return tasks;
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
