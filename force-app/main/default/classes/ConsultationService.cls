public without sharing class ConsultationService {
    // ════════════════════════════════════════════════════════════
    // INNER CLASSES
    // ════════════════════════════════════════════════════════════

    public class BookingRequest {
        public Id intakeId;
        public String consultationType;
        public List<String> attorneyIds; // one or more selected attorneys
        public String startDateTimeIso;
        public Integer durationMinutes;
        public String meetingLink;
        public String locationStreet;
        public String locationCity;
        public String locationState;
        public String locationPostalCode;
        public String locationCountry;
        public String notes;
    }

    public class ConsultationDTO {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String consultationType;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public List<AttorneyDTO> attorneys;
        @AuraEnabled
        public String scheduledStartIso;
        @AuraEnabled
        public String scheduledEndIso;
        @AuraEnabled
        public String scheduledStartLabel;
        @AuraEnabled
        public String meetingLink;
        @AuraEnabled
        public String location; // formatted display string
        @AuraEnabled
        public String locationStreet;
        @AuraEnabled
        public String locationCity;
        @AuraEnabled
        public String locationState;
        @AuraEnabled
        public String locationPostalCode;
        @AuraEnabled
        public String locationCountry;
        @AuraEnabled
        public String notes;
        @AuraEnabled
        public String cancelledReason;
        @AuraEnabled
        public Integer sequence;
    }

    public class AttorneyDTO {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String email;
        @AuraEnabled
        public String photoUrl;
    }

    public class ConflictResult {
        @AuraEnabled
        public Boolean hasConflict;
        @AuraEnabled
        public String conflictLabel;
    }

    public class IntakeStatusDTO {
        @AuraEnabled
        public Boolean isQueueOwned;
        @AuraEnabled
        public Boolean hasClient;
    }

    // ════════════════════════════════════════════════════════════
    // PUBLIC METHODS
    // ════════════════════════════════════════════════════════════

    // ── Check if intake is queue-owned or missing client ─────────
    public static IntakeStatusDTO getIntakeStatus(Id intakeId) {
        Intake__c intake = [
            SELECT Id, OwnerId, Client__c
            FROM Intake__c
            WHERE Id = :intakeId
            LIMIT 1
        ];
        IntakeStatusDTO dto = new IntakeStatusDTO();
        dto.isQueueOwned = String.valueOf(intake.OwnerId).startsWith('00G');
        dto.hasClient = intake.Client__c != null;
        return dto;
    }

    // ── Get consultations for an intake ──────────────────────────
    public static List<ConsultationDTO> getConsultations(Id intakeId) {
        List<Consultation__c> rows = [
            SELECT
                Id,
                Type__c,
                Status__c,
                Scheduled_Start__c,
                Scheduled_End__c,
                Meeting_Link__c,
                Meeting_Location__Street__s,
                Meeting_Location__City__s,
                Meeting_Location__StateCode__s,
                Meeting_Location__PostalCode__s,
                Meeting_Location__CountryCode__s,
                Notes__c,
                Cancelled_Reason__c,
                Sequence__c
            FROM Consultation__c
            WHERE Intake__c = :intakeId
            ORDER BY Scheduled_Start__c DESC
        ];

        Set<Id> consultationIds = new Map<Id, Consultation__c>(rows).keySet();
        Map<Id, List<AttorneyDTO>> attorneysByConsultation = loadAttorneysByConsultationIds(consultationIds);

        List<ConsultationDTO> result = new List<ConsultationDTO>();
        for (Consultation__c c : rows) {
            result.add(toDTO(c, attorneysByConsultation.get(c.Id)));
        }
        return result;
    }

    // ── Get attorneys by profile — NOT by Role__c ─────────────────
    // All active External App Users with the Delipat Attorney Portal
    // profile are shown. When an attorney is selected and a consultation
    // is booked, Role__c is created automatically.
    public static List<AttorneyDTO> getAttorneys(Id intakeId) {
        List<AttorneyDTO> result = new List<AttorneyDTO>();

        List<Profile> profiles = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Delipat Attorney'
            LIMIT 1
        ];
        if (profiles.isEmpty())
            return result;

        for (User u : [
            SELECT Id, Name, Email, SmallPhotoUrl
            FROM User
            WHERE IsActive = TRUE AND ProfileId = :profiles[0].Id AND ContactId != NULL // External App Users always have ContactId
            ORDER BY Name
            LIMIT 50
        ]) {
            result.add(userToAttorney(u));
        }
        return result;
    }

    // ── Check attorney calendar conflict ─────────────────────────
    // NOTE: this checks Event.OwnerId = attorneyId. Per this platform's
    // architecture, External App Users (attorneys) can never own an
    // Event — the specialist/intake manager always does. This check
    // may therefore never find a genuine conflict as currently written.
    // Left unchanged here since it's outside the scope of the current
    // request, but flagged for a follow-up conversation.
    public static ConflictResult checkConflict(Id attorneyId, String startIso, Integer durationMinutes) {
        ConflictResult res = new ConflictResult();
        res.hasConflict = false;
        try {
            DateTime startDt = DateTime.valueOfGmt(startIso.replace('T', ' '));
            DateTime endDt = startDt.addMinutes(durationMinutes);
            List<Event> conflicts = [
                SELECT Id, Subject, StartDateTime
                FROM Event
                WHERE OwnerId = :attorneyId AND StartDateTime < :endDt AND EndDateTime > :startDt
                LIMIT 1
            ];
            if (!conflicts.isEmpty()) {
                res.hasConflict = true;
                res.conflictLabel =
                    'Attorney has a conflict: ' +
                    conflicts[0].Subject +
                    ' at ' +
                    conflicts[0].StartDateTime.format('MMM d, h:mm a');
            }
        } catch (Exception e) {
            /* ignore parse errors */
        }
        return res;
    }

    // ── Book a consultation ───────────────────────────────────────
    public static ConsultationDTO book(String requestJson) {
        BookingRequest req = (BookingRequest) JSON.deserialize(requestJson, BookingRequest.class);

        if (req.attorneyIds == null || req.attorneyIds.isEmpty()) {
            throw new AuraHandledException('Please select an attorney.');
        }

        DateTime startDt = DateTime.valueOfGmt(req.startDateTimeIso.replace('T', ' '));
        DateTime endDt = startDt.addMinutes(req.durationMinutes);

        // ── Load intake ───────────────────────────────────────────
        Intake__c intake = [
            SELECT Id, Name, OwnerId, Client__c, Client__r.Name, Client__r.Email, Status__c
            FROM Intake__c
            WHERE Id = :req.intakeId
            LIMIT 1
        ];

        // ── Load all selected attorneys in one query ──────────────
        List<Id> attIds = new List<Id>();
        for (String s : req.attorneyIds)
            attIds.add((Id) s);

        List<User> attorneys = [
            SELECT Id, Name, Email, SmallPhotoUrl, ContactId
            FROM User
            WHERE Id IN :attIds AND IsActive = TRUE
        ];
        if (attorneys.isEmpty()) {
            throw new AuraHandledException('Selected attorney not found or is no longer active.');
        }

        // ── Resolve specialist — guard against queue ownership ────
        // Queue Ids start with '00G'; User Ids start with '005'.
        // Portal/External App Users cannot own Salesforce Events,
        // so the Event owner must always be an internal user.
        User specialist = null;
        if (String.valueOf(intake.OwnerId).startsWith('005')) {
            List<User> specs = [
                SELECT Id, Name, Email
                FROM User
                WHERE Id = :intake.OwnerId
                LIMIT 1
            ];
            if (!specs.isEmpty())
                specialist = specs[0];
        }

        // ── Build formatted address for Event.Location ────────────
        String formattedAddress = buildAddressString(
            req.locationStreet,
            req.locationCity,
            req.locationState,
            req.locationPostalCode,
            req.locationCountry
        );

        // ════════════════════════════════════════════════════════
        // ALL DML — emails are NOT callouts so they are safe after
        // ════════════════════════════════════════════════════════

        // ── DML 1: Salesforce Event ───────────────────────────────
        // Portal users cannot own activities — use specialist (internal
        // user) as owner, falling back to the running user if the intake
        // is queue-owned and has no specialist yet.
        Event ev = new Event(
            Subject = req.consultationType + ' — ' + intake.Name,
            WhatId = req.intakeId,
            WhoId = intake.Client__c, // null WhoId is valid on Event
            OwnerId = specialist != null ? specialist.Id : UserInfo.getUserId(),
            StartDateTime = startDt,
            EndDateTime = endDt,
            Description = req.notes,
            Location = String.isNotBlank(req.meetingLink) ? req.meetingLink : formattedAddress,
            IsReminderSet = true,
            ReminderDateTime = startDt.addMinutes(-60)
        );
        insert ev;

        // ── DML 2: Consultation__c ────────────────────────────────
        // No Attorney__c on this object — every attorney lives in
        // Consultation_Attorney__c (DML 2.5 below).
        Consultation__c c = new Consultation__c(
            Intake__c = req.intakeId,
            Type__c = req.consultationType,
            Scheduled_Start__c = startDt,
            Scheduled_End__c = endDt,
            Duration__c = req.durationMinutes,
            Status__c = 'Scheduled',
            Meeting_Link__c = req.meetingLink,
            Meeting_Location__Street__s = req.locationStreet,
            Meeting_Location__City__s = req.locationCity,
            Meeting_Location__StateCode__s = req.locationState,
            Meeting_Location__PostalCode__s = req.locationPostalCode,
            Meeting_Location__CountryCode__s = req.locationCountry,
            Notes__c = req.notes,
            Client_Email__c = intake.Client__c != null ? intake.Client__r?.Email : null,
            Event_Id__c = ev.Id,
            Sequence__c = 0,
            Confirmation_Sent__c = true
        );
        insert c;

        // ── DML 2.5: Consultation_Attorney__c junction — ALL attorneys ──
        // Sole source of truth for which attorneys are on this
        // consultation. One row per selected attorney.
        List<Consultation_Attorney__c> attorneyLinks = new List<Consultation_Attorney__c>();
        for (User att : attorneys) {
            attorneyLinks.add(new Consultation_Attorney__c(Consultation__c = c.Id, Attorney__c = att.Id));
        }
        insert attorneyLinks;

        // ── DML 3: Auto-create Role__c Attorney records ───────────
        // Fetch ContactIds for all selected attorneys in one query
        Map<Id, Id> userToContactMap = new Map<Id, Id>();
        List<Id> contactIds = new List<Id>();
        for (User att : attorneys) {
            if (att.ContactId != null) {
                userToContactMap.put(att.Id, att.ContactId);
                contactIds.add(att.ContactId);
            }
        }

        if (!contactIds.isEmpty()) {
            // Find which contacts are already Attorney roles on this intake
            Set<Id> existingContactIds = new Set<Id>();
            for (Role__c r : [
                SELECT Party__c
                FROM Role__c
                WHERE Intake__c = :req.intakeId AND Party__c IN :contactIds AND Role__c = 'Attorney'
            ]) {
                existingContactIds.add(r.Party__c);
            }

            // Insert only the missing Role__c records
            List<Role__c> rolesToInsert = new List<Role__c>();
            for (Id contactId : contactIds) {
                if (!existingContactIds.contains(contactId)) {
                    rolesToInsert.add(
                        new Role__c(Intake__c = req.intakeId, Party__c = contactId, Role__c = 'Attorney')
                    );
                }
            }
            if (!rolesToInsert.isEmpty())
                insert rolesToInsert;
        }

        // ── Send confirmation email + .ics to client + all attorneys ──
        // Messaging.sendEmail is NOT a callout; safe after DML. Sends
        // the client once and every attorney independently — see
        // sendConsultationEmails for why this replaced the old
        // per-attorney loop.
        sendConsultationEmails(c, intake, attorneys, 'REQUEST', 0, null);

        // ── Build attorneys list for the returned DTO directly from
        // the already-loaded `attorneys` list — no extra query needed. ──
        List<AttorneyDTO> attorneyDtos = new List<AttorneyDTO>();
        for (User att : attorneys) {
            attorneyDtos.add(userToAttorney(att));
        }

        // Return fresh DTO
        return toDTO(
            [
                SELECT
                    Id,
                    Type__c,
                    Status__c,
                    Scheduled_Start__c,
                    Scheduled_End__c,
                    Meeting_Link__c,
                    Meeting_Location__Street__s,
                    Meeting_Location__City__s,
                    Meeting_Location__StateCode__s,
                    Meeting_Location__PostalCode__s,
                    Meeting_Location__CountryCode__s,
                    Notes__c,
                    Cancelled_Reason__c,
                    Sequence__c
                FROM Consultation__c
                WHERE Id = :c.Id
            ],
            attorneyDtos
        );
    }

    // ── Reschedule ────────────────────────────────────────────────
    public static ConsultationDTO reschedule(Id consultationId, String newStartIso, Integer durationMinutes) {
        Consultation__c c = [
            SELECT
                Id,
                Type__c,
                Status__c,
                Duration__c,
                Scheduled_Start__c,
                Scheduled_End__c,
                Meeting_Link__c,
                Meeting_Location__Street__s,
                Meeting_Location__City__s,
                Meeting_Location__StateCode__s,
                Meeting_Location__PostalCode__s,
                Meeting_Location__CountryCode__s,
                Notes__c,
                Client_Email__c,
                Event_Id__c,
                Sequence__c,
                Intake__c,
                Intake__r.Name,
                Intake__r.OwnerId,
                Intake__r.Client__c,
                Intake__r.Client__r.Name,
                Intake__r.Client__r.Email
            FROM Consultation__c
            WHERE Id = :consultationId
            LIMIT 1
        ];

        DateTime newStart = DateTime.valueOfGmt(newStartIso.replace('T', ' '));
        DateTime newEnd = newStart.addMinutes(durationMinutes);
        Integer newSeq = (Integer) (c.Sequence__c ?? 0) + 1;

        // ── DML 1: Update Consultation__c ─────────────────────────
        c.Scheduled_Start__c = newStart;
        c.Scheduled_End__c = newEnd;
        c.Duration__c = durationMinutes;
        c.Status__c = 'Scheduled';
        c.Sequence__c = newSeq;
        c.Reminder_24h_Sent__c = false;
        c.Reminder_1h_Sent__c = false;
        update c;

        // ── DML 2: Update linked Salesforce Event ─────────────────
        if (String.isNotBlank(c.Event_Id__c)) {
            try {
                Event ev = [SELECT Id FROM Event WHERE Id = :c.Event_Id__c LIMIT 1];
                ev.StartDateTime = newStart;
                ev.EndDateTime = newEnd;
                update ev;
            } catch (Exception ex) {
                /* Event may have been deleted manually */
            }
        }

        // ── Load ALL attorneys on this consultation ────────────────
        // Consultation_Attorney__c is the ONLY source — no fallback
        // to a single field. A consultation with zero attorney links
        // simply notifies zero attorneys, which is correct.
        Set<Id> attorneyUserIds = new Set<Id>();
        for (Consultation_Attorney__c ca : [
            SELECT Attorney__c
            FROM Consultation_Attorney__c
            WHERE Consultation__c = :consultationId
        ]) {
            attorneyUserIds.add(ca.Attorney__c);
        }
        List<User> attorneyUsers = attorneyUserIds.isEmpty()
            ? new List<User>()
            : [SELECT Id, Name, Email, SmallPhotoUrl FROM User WHERE Id IN :attorneyUserIds];

        // ── Send reschedule email to client once + every attorney ──
        sendConsultationEmails(c, c.Intake__r, attorneyUsers, 'REQUEST', newSeq, null);

        List<AttorneyDTO> attorneyDtos = new List<AttorneyDTO>();
        for (User att : attorneyUsers) {
            attorneyDtos.add(userToAttorney(att));
        }

        return toDTO(
            [
                SELECT
                    Id,
                    Type__c,
                    Status__c,
                    Scheduled_Start__c,
                    Scheduled_End__c,
                    Meeting_Link__c,
                    Meeting_Location__Street__s,
                    Meeting_Location__City__s,
                    Meeting_Location__StateCode__s,
                    Meeting_Location__PostalCode__s,
                    Meeting_Location__CountryCode__s,
                    Notes__c,
                    Cancelled_Reason__c,
                    Sequence__c
                FROM Consultation__c
                WHERE Id = :consultationId
            ],
            attorneyDtos
        );
    }

    // ── Cancel ────────────────────────────────────────────────────
    public static void cancel(Id consultationId, String reason) {
        Consultation__c c = [
            SELECT
                Id,
                Status__c,
                Sequence__c,
                Type__c,
                Scheduled_Start__c,
                Scheduled_End__c,
                Meeting_Link__c,
                Meeting_Location__Street__s,
                Meeting_Location__City__s,
                Meeting_Location__StateCode__s,
                Meeting_Location__PostalCode__s,
                Meeting_Location__CountryCode__s,
                Notes__c,
                Client_Email__c,
                Event_Id__c,
                Intake__c,
                Intake__r.Name,
                Intake__r.OwnerId,
                Intake__r.Client__c,
                Intake__r.Client__r.Name,
                Intake__r.Client__r.Email
            FROM Consultation__c
            WHERE Id = :consultationId
            LIMIT 1
        ];

        Integer cancelSeq = (Integer) (c.Sequence__c ?? 0) + 1;

        // ── DML 1: Update Consultation__c ─────────────────────────
        c.Status__c = 'Cancelled';
        c.Cancelled_Reason__c = reason;
        c.Cancelled_At__c = DateTime.now();
        c.Sequence__c = cancelSeq;
        update c;

        // ── DML 2: Delete Salesforce Event ────────────────────────
        if (String.isNotBlank(c.Event_Id__c)) {
            try {
                delete [SELECT Id FROM Event WHERE Id = :c.Event_Id__c LIMIT 1];
            } catch (Exception ex) {
                /* already deleted */
            }
        }

        // ── Load ALL attorneys on this consultation ────────────────
        // PREVIOUSLY cancel() never loaded or emailed any attorney at
        // all — only the client received a cancellation notice, via a
        // standalone client-only .ics send. Fixed below: every linked
        // attorney now gets the cancellation notice too.
        Set<Id> attorneyUserIds = new Set<Id>();
        for (Consultation_Attorney__c ca : [
            SELECT Attorney__c
            FROM Consultation_Attorney__c
            WHERE Consultation__c = :consultationId
        ]) {
            attorneyUserIds.add(ca.Attorney__c);
        }
        List<User> attorneyUsers = attorneyUserIds.isEmpty()
            ? new List<User>()
            : [SELECT Id, Name, Email FROM User WHERE Id IN :attorneyUserIds];

        // ── Send cancellation notice to client once + every attorney ──
        sendConsultationEmails(c, c.Intake__r, attorneyUsers, 'CANCEL', cancelSeq, reason);
    }

    // ── Update status (Complete / No Show) ────────────────────────
    public static void updateStatus(Id consultationId, String newStatus) {
        update new Consultation__c(Id = consultationId, Status__c = newStatus);
    }

    // ── Send reminders — called by ConsultationReminderScheduler ──
    public static void sendReminders() {
        DateTime now = DateTime.now();
        DateTime h24From = now.addMinutes(23 * 60);
        DateTime h24To = now.addMinutes(25 * 60);
        DateTime h1From = now.addMinutes(55);
        DateTime h1To = now.addMinutes(70);

        List<Consultation__c> upcoming = [
            SELECT
                Id,
                Type__c,
                Status__c,
                Scheduled_Start__c,
                Scheduled_End__c,
                Meeting_Link__c,
                Meeting_Location__Street__s,
                Meeting_Location__City__s,
                Meeting_Location__StateCode__s,
                Meeting_Location__PostalCode__s,
                Meeting_Location__CountryCode__s,
                Notes__c,
                Client_Email__c,
                Sequence__c,
                Reminder_24h_Sent__c,
                Reminder_1h_Sent__c,
                Intake__c,
                Intake__r.Name,
                Intake__r.OwnerId
            FROM Consultation__c
            WHERE
                Status__c IN ('Scheduled', 'Confirmed')
                AND ((Scheduled_Start__c >= :h24From
                AND Scheduled_Start__c <= :h24To
                AND Reminder_24h_Sent__c = FALSE)
                OR (Scheduled_Start__c >= :h1From
                AND Scheduled_Start__c <= :h1To
                AND Reminder_1h_Sent__c = FALSE))
        ];
        if (upcoming.isEmpty())
            return;

        // Batch-load every attorney per consultation via the junction
        // object — a consultation with multiple attorneys reminds all
        // of them, not just one.
        Set<Id> consultationIds = new Map<Id, Consultation__c>(upcoming).keySet();
        Map<Id, List<AttorneyDTO>> attorneysByConsultation = loadAttorneysByConsultationIds(consultationIds);

        // Load custom notification type for in-app
        List<CustomNotificationType> notifTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = 'Intake_Assignment'
            LIMIT 1
        ];
        Id notifTypeId = notifTypes.isEmpty() ? null : notifTypes[0].Id;

        // Load specialists — only for user-owned intakes
        Set<Id> ownerIds = new Set<Id>();
        for (Consultation__c c : upcoming) {
            if (String.valueOf(c.Intake__r.OwnerId).startsWith('005')) {
                ownerIds.add(c.Intake__r.OwnerId);
            }
        }
        Map<Id, User> specialistMap = ownerIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([SELECT Id, Name, Email FROM User WHERE Id IN :ownerIds]);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Consultation__c> toUpdate = new List<Consultation__c>();

        for (Consultation__c c : upcoming) {
            Boolean is24h = c.Scheduled_Start__c >= h24From && c.Scheduled_Start__c <= h24To && !c.Reminder_24h_Sent__c;
            Boolean is1h = c.Scheduled_Start__c >= h1From && c.Scheduled_Start__c <= h1To && !c.Reminder_1h_Sent__c;
            if (!is24h && !is1h)
                continue;

            String label = is1h ? '1 hour' : '24 hours';
            String subject = 'Reminder: ' + c.Type__c + ' in ' + label + ' — ' + c.Intake__r.Name;
            String meetingInfo = String.isNotBlank(c.Meeting_Link__c)
                ? '<p><a href="' + c.Meeting_Link__c + '">Join Meeting</a></p>'
                : '';

            List<AttorneyDTO> attorneysForThis = attorneysByConsultation.get(c.Id);
            if (attorneysForThis == null)
                attorneysForThis = new List<AttorneyDTO>();

            // Email to client
            if (String.isNotBlank(c.Client_Email__c)) {
                String ics = generateIcs(
                    c.Id,
                    c.Type__c + ' — ' + c.Intake__r.Name,
                    'Reminder: Your ' + c.Type__c.toLowerCase() + ' is in ' + label,
                    c.Meeting_Link__c,
                    c.Scheduled_Start__c,
                    c.Scheduled_End__c,
                    'REQUEST',
                    (Integer) (c.Sequence__c ?? 0)
                );
                Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
                em.setToAddresses(new List<String>{ c.Client_Email__c });
                em.setSubject(subject);
                em.setHtmlBody(reminderHtml(c, label, 'client', meetingInfo));
                em.setFileAttachments(new List<Messaging.EmailFileAttachment>{ icsAttachment(ics, 'REQUEST') });
                em.setSaveAsActivity(false);
                emails.add(em);
            }

            // Email to EVERY attorney on this consultation
            for (AttorneyDTO att : attorneysForThis) {
                if (String.isBlank(att.email))
                    continue;
                Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
                em.setToAddresses(new List<String>{ att.email });
                em.setSubject(subject);
                em.setHtmlBody(reminderHtml(c, label, 'attorney', meetingInfo));
                em.setSaveAsActivity(false);
                emails.add(em);
            }

            // In-app notification to specialist (only for user-owned intakes)
            User specialist = specialistMap.get(c.Intake__r.OwnerId);
            if (notifTypeId != null && specialist != null) {
                List<String> attorneyNames = new List<String>();
                for (AttorneyDTO att : attorneysForThis)
                    attorneyNames.add(att.name);
                String attorneyLabel = attorneyNames.isEmpty() ? 'the attorney' : String.join(attorneyNames, ', ');

                try {
                    Messaging.CustomNotification notif = new Messaging.CustomNotification();
                    notif.setNotificationTypeId(notifTypeId);
                    notif.setTargetId(c.Intake__c);
                    notif.setTitle('Meeting in ' + label + ' — ' + c.Intake__r.Name);
                    notif.setBody(
                        c.Type__c + ' with ' + attorneyLabel + ' at ' + c.Scheduled_Start__c.format('h:mm a')
                    );
                    notif.send(new Set<String>{ specialist.Id });
                } catch (Exception ex) {
                    /* silent — notification failure shouldn't crash */
                }
            }

            Consultation__c patch = new Consultation__c(Id = c.Id);
            if (is24h)
                patch.Reminder_24h_Sent__c = true;
            if (is1h)
                patch.Reminder_1h_Sent__c = true;
            toUpdate.add(patch);
        }

        if (!emails.isEmpty()) {
            try {
                // allOrNone=false — same defensive pattern used in
                // sendConsultationEmails: one bad recipient across this
                // entire scheduled run should never silently block
                // every reminder in the batch.
                List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        for (Messaging.SendEmailError err : results[i].getErrors()) {
                            System.debug(LoggingLevel.ERROR, 'Reminder email failed: ' + err.getMessage());
                        }
                    }
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Reminder emails failed: ' + ex.getMessage());
            }
        }
        if (!toUpdate.isEmpty())
            update toUpdate;
    }

    // ════════════════════════════════════════════════════════════
    // PRIVATE HELPERS
    // ════════════════════════════════════════════════════════════

    // ── Batch-load all attorneys per consultation via the junction
    // object. Returns a map keyed by Consultation__c Id. ──
    private static Map<Id, List<AttorneyDTO>> loadAttorneysByConsultationIds(Set<Id> consultationIds) {
        Map<Id, List<AttorneyDTO>> result = new Map<Id, List<AttorneyDTO>>();
        if (consultationIds.isEmpty())
            return result;

        for (Consultation_Attorney__c ca : [
            SELECT Consultation__c, Attorney__c, Attorney__r.Name, Attorney__r.Email, Attorney__r.SmallPhotoUrl
            FROM Consultation_Attorney__c
            WHERE Consultation__c IN :consultationIds
        ]) {
            if (!result.containsKey(ca.Consultation__c)) {
                result.put(ca.Consultation__c, new List<AttorneyDTO>());
            }
            AttorneyDTO d = new AttorneyDTO();
            d.id = ca.Attorney__c;
            d.name = ca.Attorney__r?.Name;
            d.email = ca.Attorney__r?.Email;
            d.photoUrl = ca.Attorney__r?.SmallPhotoUrl;
            result.get(ca.Consultation__c).add(d);
        }
        return result;
    }

    // ── Unified email dispatch for book/reschedule/cancel ──────────────
    // PREVIOUSLY named sendConfirmationEmails and called once PER
    // ATTORNEY, which (a) re-sent a duplicate confirmation to the
    // CLIENT on every iteration when multiple attorneys were selected,
    // and (b) used the default Messaging.sendEmail(emails) with
    // allOrNone=true, so a single bad recipient in that small 2-item
    // batch (client + 1 attorney) silently killed BOTH emails for that
    // call — and since the client was rebuilt into every attorney's
    // call, one broken recipient could effectively block every
    // attorney's email across the whole loop. cancel() additionally
    // never emailed any attorney at all.
    //
    // Fixed: the client is emailed exactly ONCE regardless of how many
    // attorneys are on the consultation. Every attorney gets their own
    // independent email. All recipients for this action are sent
    // together via Messaging.sendEmail(emails, false) — allOrNone=false
    // — so one bad address never silently blocks anyone else, and each
    // failure is logged individually with the exact recipient and error.
    private static void sendConsultationEmails(
        Consultation__c c,
        Intake__c intake,
        List<User> attorneys,
        String method, // 'REQUEST' (book/reschedule) or 'CANCEL'
        Integer sequence,
        String cancelReason
    ) {
        // null unless method == 'CANCEL'
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        String locFormatted = buildAddressString(
            c.Meeting_Location__Street__s,
            c.Meeting_Location__City__s,
            c.Meeting_Location__StateCode__s,
            c.Meeting_Location__PostalCode__s,
            c.Meeting_Location__CountryCode__s
        );
        String meetingInfo = String.isNotBlank(c.Meeting_Link__c)
            ? '<p><strong>Meeting Link:</strong> <a href="' + c.Meeting_Link__c + '">' + c.Meeting_Link__c + '</a></p>'
            : (String.isNotBlank(locFormatted) ? '<p><strong>Location:</strong> ' + locFormatted + '</p>' : '');

        String attorneyNamesJoined = joinAttorneyNames(attorneys);

        // ── Client — sent exactly once ─────────────────────────────
        String clientEmail = c.Client_Email__c;
        if (String.isBlank(clientEmail) && intake.Client__c != null) {
            clientEmail = intake.Client__r?.Email;
        }
        if (String.isNotBlank(clientEmail)) {
            String ics = generateIcs(
                c.Id,
                c.Type__c + ' — ' + intake.Name,
                buildIcsDescription(intake, attorneyNamesJoined, c.Meeting_Link__c),
                String.isNotBlank(c.Meeting_Link__c) ? c.Meeting_Link__c : locFormatted,
                c.Scheduled_Start__c,
                c.Scheduled_End__c,
                method,
                sequence
            );
            Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
            em.setToAddresses(new List<String>{ clientEmail });
            if (method == 'CANCEL') {
                em.setSubject('Cancelled: ' + c.Type__c + ' — ' + intake.Name);
                em.setHtmlBody(cancellationHtml(c, intake, attorneyNamesJoined, cancelReason, 'client'));
            } else {
                em.setSubject((sequence > 0 ? 'Updated: ' : 'Confirmed: ') + c.Type__c + ' — ' + intake.Name);
                em.setHtmlBody(confirmationHtml(c, intake, attorneyNamesJoined, meetingInfo, 'client'));
            }
            em.setFileAttachments(new List<Messaging.EmailFileAttachment>{ icsAttachment(ics, method) });
            em.setSaveAsActivity(false);
            emails.add(em);
        }

        // ── Every attorney — each independent ────────────────────────
        for (User attorney : attorneys) {
            if (String.isBlank(attorney.Email))
                continue;
            String ics = generateIcs(
                c.Id,
                c.Type__c + ' — ' + intake.Name,
                buildIcsDescription(intake, attorney.Name, c.Meeting_Link__c),
                String.isNotBlank(c.Meeting_Link__c) ? c.Meeting_Link__c : locFormatted,
                c.Scheduled_Start__c,
                c.Scheduled_End__c,
                method,
                sequence
            );
            Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
            em.setToAddresses(new List<String>{ attorney.Email });
            if (method == 'CANCEL') {
                em.setSubject('Cancelled: ' + c.Type__c + ' — ' + intake.Name);
                em.setHtmlBody(cancellationHtml(c, intake, attorney.Name, cancelReason, 'attorney'));
            } else {
                em.setSubject(
                    (sequence > 0 ? 'Updated: ' : 'New Consultation: ') +
                        intake.Name +
                        ' — ' +
                        c.Scheduled_Start__c.format('MMM d, h:mm a')
                );
                em.setHtmlBody(confirmationHtml(c, intake, attorney.Name, meetingInfo, 'attorney'));
            }
            em.setFileAttachments(new List<Messaging.EmailFileAttachment>{ icsAttachment(ics, method) });
            em.setSaveAsActivity(false);
            emails.add(em);
        }

        if (emails.isEmpty())
            return;

        try {
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    String toAddr = (emails[i].getToAddresses() != null && !emails[i].getToAddresses().isEmpty())
                        ? emails[i].getToAddresses()[0]
                        : '(unknown)';
                    for (Messaging.SendEmailError err : results[i].getErrors()) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'Consultation email FAILED to ' +
                                toAddr +
                                ' — ' +
                                err.getStatusCode() +
                                ': ' +
                                err.getMessage()
                        );
                    }
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Consultation email dispatch failed: ' + ex.getMessage());
        }
    }

    private static String joinAttorneyNames(List<User> attorneys) {
        List<String> names = new List<String>();
        for (User u : attorneys) {
            if (String.isNotBlank(u.Name))
                names.add(u.Name);
        }
        return names.isEmpty() ? '—' : String.join(names, ', ');
    }

    private static String buildIcsDescription(Intake__c intake, String attorneyLabel, String meetingLink) {
        return 'Intake: ' +
            intake.Name +
            '\\n' +
            'Client: ' +
            (intake.Client__c != null && intake.Client__r?.Name != null ? intake.Client__r.Name : '—') +
            '\\n' +
            'Attorney: ' +
            attorneyLabel +
            '\\n' +
            (String.isNotBlank(meetingLink) ? 'Join: ' + meetingLink : '');
    }

    // ── Build .ics calendar file ──────────────────────────────────
    @TestVisible
    static String generateIcs(
        Id uid,
        String summary,
        String description,
        String location,
        DateTime startDt,
        DateTime endDt,
        String method,
        Integer sequence
    ) {
        String s = startDt.formatGmt('yyyyMMdd') + 'T' + startDt.formatGmt('HHmmss') + 'Z';
        String e = endDt.formatGmt('yyyyMMdd') + 'T' + endDt.formatGmt('HHmmss') + 'Z';
        String n = DateTime.now().formatGmt('yyyyMMdd') + 'T' + DateTime.now().formatGmt('HHmmss') + 'Z';

        return 'BEGIN:VCALENDAR\r\n' +
            'VERSION:2.0\r\n' +
            'PRODID:-//Delipat PI Platform//EN\r\n' +
            'METHOD:' +
            method +
            '\r\n' +
            'BEGIN:VEVENT\r\n' +
            'UID:delipat-' +
            String.valueOf(uid) +
            '@delipat.com\r\n' +
            'DTSTAMP:' +
            n +
            '\r\n' +
            'DTSTART:' +
            s +
            '\r\n' +
            'DTEND:' +
            e +
            '\r\n' +
            'SUMMARY:' +
            escapeIcs(summary) +
            '\r\n' +
            'DESCRIPTION:' +
            escapeIcs(description) +
            '\r\n' +
            'LOCATION:' +
            escapeIcs(location ?? '') +
            '\r\n' +
            'SEQUENCE:' +
            sequence +
            '\r\n' +
            (method == 'CANCEL' ? 'STATUS:CANCELLED\r\n' : '') +
            'END:VEVENT\r\n' +
            'END:VCALENDAR';
    }

    // ── Confirmation email HTML ───────────────────────────────────
    private static String confirmationHtml(
        Consultation__c c,
        Intake__c intake,
        String attorneyDisplayName,
        String meetingInfo,
        String recipient
    ) {
        String timeLabel =
            c.Scheduled_Start__c.format('EEEE, MMMM d, yyyy') +
            ' at ' +
            c.Scheduled_Start__c.format('h:mm a z');

        String clientFirst = intake.Client__c != null &&
            intake.Client__r?.Name != null
            ? intake.Client__r.Name.split(' ')[0]
            : 'there';
        String greeting = recipient == 'client'
            ? 'Hi ' + clientFirst + ','
            : 'Hi ' + attorneyDisplayName.split(' ')[0] + ',';

        String clientDisplay = intake.Client__c != null &&
            intake.Client__r?.Name != null
            ? intake.Client__r.Name
            : 'the client';
        String intro = recipient == 'client'
            ? 'Your ' + c.Type__c.toLowerCase() + ' has been confirmed.'
            : 'You have a new ' + c.Type__c.toLowerCase() + ' scheduled with ' + clientDisplay + '.';

        return '<!DOCTYPE html><html><body>' +
            '<div style="font-family:Helvetica Neue,Helvetica,Arial,sans-serif;' +
            'max-width:600px;margin:0 auto;border:1px solid #e0e5ee;' +
            'border-radius:8px;overflow:hidden;">' +
            '<div style="background:#04152f;padding:20px 28px;">' +
            '<p style="color:#fff;font-size:18px;font-weight:700;margin:0;">' +
            'Delipat Law Group</p></div>' +
            '<div style="background:#e0f2fe;border-left:4px solid #0284c7;padding:14px 20px;">' +
            '<p style="color:#0c4a6e;font-weight:700;margin:0;font-size:15px;">' +
            c.Type__c +
            ' Confirmed</p></div>' +
            '<div style="padding:28px;background:#fff;">' +
            '<p style="color:#333;font-size:14px;margin:0 0 8px;">' +
            greeting +
            '</p>' +
            '<p style="color:#333;font-size:14px;margin:0 0 20px;">' +
            intro +
            '</p>' +
            '<table style="width:100%;border-collapse:collapse;font-size:13px;' +
            'margin-bottom:20px;">' +
            tableRow('Date & Time', timeLabel) +
            tableRow('Duration', c.Duration__c != null ? c.Duration__c + ' minutes' : '—') +
            tableRow('Attorney', attorneyDisplayName) +
            tableRow('Intake', intake.Name) +
            '</table>' +
            meetingInfo +
            '<p style="color:#555;font-size:12px;margin-top:16px;">' +
            'A calendar invite (.ics) is attached — open it to add this to your calendar.' +
            '</p></div>' +
            '<div style="padding:16px 28px;background:#f8f9fb;' +
            'border-top:1px solid #e0e5ee;">' +
            '<p style="color:#aaa;font-size:11px;margin:0;">' +
            'Delipat PI Platform · Automated notification · Do not reply' +
            '</p></div></div></body></html>';
    }

    // ── Cancellation email HTML — NEW, shared by client + attorneys ──
    private static String cancellationHtml(
        Consultation__c c,
        Intake__c intake,
        String attorneyDisplayName,
        String cancelReason,
        String recipient
    ) {
        String timeLabel =
            c.Scheduled_Start__c.format('EEEE, MMMM d, yyyy') +
            ' at ' +
            c.Scheduled_Start__c.format('h:mm a z');

        String clientFirst = intake.Client__c != null &&
            intake.Client__r?.Name != null
            ? intake.Client__r.Name.split(' ')[0]
            : 'there';
        String greeting = recipient == 'client'
            ? 'Hi ' + clientFirst + ','
            : 'Hi ' + attorneyDisplayName.split(' ')[0] + ',';

        String reasonLine = String.isNotBlank(cancelReason)
            ? '<p style="color:#333;font-size:13px;margin:0 0 16px;"><strong>Reason:</strong> ' + cancelReason + '</p>'
            : '';

        return '<!DOCTYPE html><html><body>' +
            '<div style="font-family:Helvetica Neue,Helvetica,Arial,sans-serif;' +
            'max-width:600px;margin:0 auto;border:1px solid #e0e5ee;border-radius:8px;overflow:hidden;">' +
            '<div style="background:#04152f;padding:20px 28px;">' +
            '<p style="color:#fff;font-size:18px;font-weight:700;margin:0;">Delipat Law Group</p></div>' +
            '<div style="background:#fef2f2;border-left:4px solid #dc2626;padding:14px 20px;">' +
            '<p style="color:#dc2626;font-weight:700;margin:0;font-size:15px;">' +
            c.Type__c +
            ' Cancelled</p></div>' +
            '<div style="padding:28px;background:#fff;">' +
            '<p style="color:#333;font-size:14px;margin:0 0 8px;">' +
            greeting +
            '</p>' +
            '<p style="color:#333;font-size:14px;margin:0 0 12px;">' +
            'Your ' +
            c.Type__c.toLowerCase() +
            ' scheduled for <strong>' +
            timeLabel +
            '</strong> has been cancelled.</p>' +
            reasonLine +
            '<p style="color:#555;font-size:12px;">We will be in touch to reschedule if needed.</p>' +
            '</div>' +
            '<div style="padding:16px 28px;background:#f8f9fb;border-top:1px solid #e0e5ee;">' +
            '<p style="color:#aaa;font-size:11px;margin:0;">Delipat PI Platform · Automated notification · Do not reply</p>' +
            '</div></div></body></html>';
    }

    // ── Reminder email HTML ───────────────────────────────────────
    private static String reminderHtml(Consultation__c c, String timeUntil, String recipient, String meetingInfo) {
        String timeLabel =
            c.Scheduled_Start__c.format('h:mm a z') +
            ' on ' +
            c.Scheduled_Start__c.format('MMMM d, yyyy');

        return '<!DOCTYPE html><html><body>' +
            '<div style="font-family:Helvetica Neue,Helvetica,Arial,sans-serif;' +
            'max-width:600px;margin:0 auto;border:1px solid #e0e5ee;' +
            'border-radius:8px;overflow:hidden;">' +
            '<div style="background:#04152f;padding:20px 28px;">' +
            '<p style="color:#fff;font-size:18px;font-weight:700;margin:0;">' +
            'Delipat Law Group</p></div>' +
            '<div style="background:#fef9c3;border-left:4px solid #eab308;padding:14px 20px;">' +
            '<p style="color:#713f12;font-weight:700;margin:0;">' +
            'Meeting Reminder — in ' +
            timeUntil +
            '</p></div>' +
            '<div style="padding:28px;background:#fff;">' +
            '<p style="color:#333;font-size:14px;margin:0 0 12px;">' +
            'Your ' +
            c.Type__c.toLowerCase() +
            ' is coming up.</p>' +
            '<p style="font-size:16px;font-weight:700;color:#04152f;margin:0 0 16px;">' +
            timeLabel +
            '</p>' +
            meetingInfo +
            '</div>' +
            '<div style="padding:16px 28px;background:#f8f9fb;' +
            'border-top:1px solid #e0e5ee;">' +
            '<p style="color:#aaa;font-size:11px;margin:0;">' +
            'Delipat PI Platform · Do not reply</p>' +
            '</div></div></body></html>';
    }

    // ── Utility: build readable address from sub-fields ───────────
    private static String buildAddressString(String street, String city, String state, String postal, String country) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(street))
            parts.add(street);
        if (String.isNotBlank(city))
            parts.add(city);
        if (String.isNotBlank(state))
            parts.add(state);
        if (String.isNotBlank(postal))
            parts.add(postal);
        if (String.isNotBlank(country))
            parts.add(country);
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    // ── Utility: escape special chars for .ics format ────────────
    private static String escapeIcs(String val) {
        if (val == null)
            return '';
        return val.replace('\\', '\\\\').replace(';', '\\;').replace(',', '\\,').replace('\n', '\\n');
    }

    // ── Utility: build .ics email attachment ──────────────────────
    private static Messaging.EmailFileAttachment icsAttachment(String icsContent, String method) {
        Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
        att.setFileName('consultation.ics');
        att.setBody(Blob.valueOf(icsContent));
        att.setContentType('text/calendar; charset=UTF-8; method=' + method);
        return att;
    }

    // ── Utility: HTML email table row ─────────────────────────────
    private static String tableRow(String label, String value) {
        return '<tr>' +
            '<td style="padding:10px 14px;background:#f4f6f9;color:#777;' +
            'font-size:11px;text-transform:uppercase;letter-spacing:0.05em;width:35%;">' +
            label +
            '</td>' +
            '<td style="padding:10px 14px;font-weight:600;color:#04152f;">' +
            (value ?? '—') +
            '</td></tr>';
    }

    // ── Map Consultation__c to ConsultationDTO ────────────────────
    // Attorney data comes exclusively from Consultation_Attorney__c.
    // A consultation with zero linked attorneys returns an empty list.
    private static ConsultationDTO toDTO(Consultation__c c, List<AttorneyDTO> attorneysList) {
        ConsultationDTO d = new ConsultationDTO();
        d.id = c.Id;
        d.consultationType = c.Type__c;
        d.status = c.Status__c;
        d.attorneys = attorneysList != null ? attorneysList : new List<AttorneyDTO>();
        d.scheduledStartIso = c.Scheduled_Start__c != null
            ? c.Scheduled_Start__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
            : null;
        d.scheduledEndIso = c.Scheduled_End__c != null
            ? c.Scheduled_End__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
            : null;
        d.scheduledStartLabel = c.Scheduled_Start__c != null
            ? c.Scheduled_Start__c.format('EEE, MMM d · h:mm a')
            : null;
        d.meetingLink = c.Meeting_Link__c;
        d.locationStreet = c.Meeting_Location__Street__s;
        d.locationCity = c.Meeting_Location__City__s;
        d.locationState = c.Meeting_Location__StateCode__s;
        d.locationPostalCode = c.Meeting_Location__PostalCode__s;
        d.locationCountry = c.Meeting_Location__CountryCode__s;
        d.location = buildAddressString(
            c.Meeting_Location__Street__s,
            c.Meeting_Location__City__s,
            c.Meeting_Location__StateCode__s,
            c.Meeting_Location__PostalCode__s,
            c.Meeting_Location__CountryCode__s
        );
        d.notes = c.Notes__c;
        d.cancelledReason = c.Cancelled_Reason__c;
        d.sequence = c.Sequence__c != null ? (Integer) c.Sequence__c : 0;
        return d;
    }

    // ── Map User to AttorneyDTO ───────────────────────────────────
    private static AttorneyDTO userToAttorney(User u) {
        AttorneyDTO d = new AttorneyDTO();
        d.id = u.Id;
        d.name = u.Name;
        d.email = u.Email;
        d.photoUrl = u.SmallPhotoUrl;
        return d;
    }
}