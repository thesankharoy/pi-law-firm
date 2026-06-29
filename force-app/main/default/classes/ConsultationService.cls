public without sharing class ConsultationService {
    // ════════════════════════════════════════════════════════════
    // INNER CLASSES
    // ════════════════════════════════════════════════════════════

    public class BookingRequest {
        public Id intakeId;
        public String consultationType;
        public List<String> attorneyIds; // accepts list; uses index 0 as primary
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
        public Id attorneyId;
        @AuraEnabled
        public String attorneyName;
        @AuraEnabled
        public String attorneyPhoto;
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
        List<ConsultationDTO> result = new List<ConsultationDTO>();
        for (Consultation__c c : [
            SELECT
                Id,
                Type__c,
                Status__c,
                Attorney__c,
                Attorney__r.Name,
                Attorney__r.SmallPhotoUrl,
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
        ]) {
            result.add(toDTO(c));
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
        User primaryAttorney = attorneys[0];

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
        Consultation__c c = new Consultation__c(
            Intake__c = req.intakeId,
            Type__c = req.consultationType,
            Attorney__c = primaryAttorney.Id,
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

        // ── Send confirmation email + .ics to each attorney + client ─
        // Messaging.sendEmail is NOT a callout; safe after DML
        for (User att : attorneys) {
            sendConfirmationEmails(c, intake, att, specialist, 'REQUEST', 0);
        }

        // Return fresh DTO
        return toDTO(
            [
                SELECT
                    Id,
                    Type__c,
                    Status__c,
                    Attorney__c,
                    Attorney__r.Name,
                    Attorney__r.SmallPhotoUrl,
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
            ]
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
                Attorney__c,
                Attorney__r.Name,
                Attorney__r.Email,
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

        // ── Resolve specialist ────────────────────────────────────
        User specialist = null;
        if (String.valueOf(c.Intake__r.OwnerId).startsWith('005')) {
            List<User> specs = [
                SELECT Id, Name, Email
                FROM User
                WHERE Id = :c.Intake__r.OwnerId
                LIMIT 1
            ];
            if (!specs.isEmpty())
                specialist = specs[0];
        }

        // ── Send reschedule email ─────────────────────────────────
        User attorney = [
            SELECT Id, Name, Email, SmallPhotoUrl
            FROM User
            WHERE Id = :c.Attorney__c
            LIMIT 1
        ];
        sendConfirmationEmails(c, c.Intake__r, attorney, specialist, 'REQUEST', newSeq);

        return toDTO(
            [
                SELECT
                    Id,
                    Type__c,
                    Status__c,
                    Attorney__c,
                    Attorney__r.Name,
                    Attorney__r.SmallPhotoUrl,
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
            ]
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
                Attorney__c,
                Attorney__r.Name,
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
                Intake__r.Client__r.Name,
                Intake__r.OwnerId
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

        // ── Send cancellation .ics ────────────────────────────────
        if (String.isNotBlank(c.Client_Email__c)) {
            String locFormatted = buildAddressString(
                c.Meeting_Location__Street__s,
                c.Meeting_Location__City__s,
                c.Meeting_Location__StateCode__s,
                c.Meeting_Location__PostalCode__s,
                c.Meeting_Location__CountryCode__s
            );
            String ics = generateIcs(
                c.Id,
                c.Type__c + ' — ' + c.Intake__r.Name,
                'This meeting has been cancelled. Reason: ' + (String.isNotBlank(reason) ? reason : 'No reason given.'),
                String.isNotBlank(c.Meeting_Link__c) ? c.Meeting_Link__c : locFormatted,
                c.Scheduled_Start__c,
                c.Scheduled_End__c,
                'CANCEL',
                cancelSeq
            );
            sendIcsEmail(
                new List<String>{ c.Client_Email__c },
                'Cancelled: ' + c.Type__c + ' — ' + c.Intake__r.Name,
                '<p>Your ' + c.Type__c.toLowerCase() + ' has been cancelled. We will be in touch to reschedule.</p>',
                ics,
                'CANCEL'
            );
        }
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
                Attorney__c,
                Attorney__r.Name,
                Attorney__r.Email,
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

            // Email to attorney
            if (String.isNotBlank(c.Attorney__r?.Email)) {
                Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
                em.setToAddresses(new List<String>{ c.Attorney__r.Email });
                em.setSubject(subject);
                em.setHtmlBody(reminderHtml(c, label, 'attorney', meetingInfo));
                em.setSaveAsActivity(false);
                emails.add(em);
            }

            // In-app notification to specialist (only for user-owned intakes)
            User specialist = specialistMap.get(c.Intake__r.OwnerId);
            if (notifTypeId != null && specialist != null) {
                try {
                    Messaging.CustomNotification notif = new Messaging.CustomNotification();
                    notif.setNotificationTypeId(notifTypeId);
                    notif.setTargetId(c.Intake__c);
                    notif.setTitle('Meeting in ' + label + ' — ' + c.Intake__r.Name);
                    notif.setBody(
                        c.Type__c + ' with ' + c.Attorney__r.Name + ' at ' + c.Scheduled_Start__c.format('h:mm a')
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
                Messaging.sendEmail(emails);
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

    // ── Confirmation email + .ics for one attorney ────────────────
    private static void sendConfirmationEmails(
        Consultation__c c,
        Intake__c intake,
        User attorney,
        User specialist,
        String method,
        Integer sequence
    ) {
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

        String ics = generateIcs(
            c.Id,
            c.Type__c + ' — ' + intake.Name,
            'Intake: ' +
                intake.Name +
                '\\n' +
                'Client: ' +
                (intake.Client__c != null && intake.Client__r?.Name != null ? intake.Client__r.Name : '—') +
                '\\n' +
                'Attorney: ' +
                attorney.Name +
                '\\n' +
                (String.isNotBlank(c.Meeting_Link__c) ? 'Join: ' + c.Meeting_Link__c : ''),
            String.isNotBlank(c.Meeting_Link__c) ? c.Meeting_Link__c : locFormatted,
            c.Scheduled_Start__c,
            c.Scheduled_End__c,
            method,
            sequence
        );

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        // Client email + .ics (only if a client exists)
        String clientEmail = c.Client_Email__c;
        if (String.isBlank(clientEmail) && intake.Client__c != null) {
            clientEmail = intake.Client__r?.Email;
        }
        if (String.isNotBlank(clientEmail)) {
            Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
            em.setToAddresses(new List<String>{ clientEmail });
            em.setSubject((sequence > 0 ? 'Updated: ' : 'Confirmed: ') + c.Type__c + ' — ' + intake.Name);
            em.setHtmlBody(confirmationHtml(c, intake, attorney, meetingInfo, 'client'));
            em.setFileAttachments(new List<Messaging.EmailFileAttachment>{ icsAttachment(ics, method) });
            em.setSaveAsActivity(false);
            emails.add(em);
        }

        // Attorney email + .ics
        if (String.isNotBlank(attorney.Email)) {
            Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
            em.setToAddresses(new List<String>{ attorney.Email });
            em.setSubject(
                (sequence > 0 ? 'Updated: ' : 'New Consultation: ') +
                    intake.Name +
                    ' — ' +
                    c.Scheduled_Start__c.format('MMM d, h:mm a')
            );
            em.setHtmlBody(confirmationHtml(c, intake, attorney, meetingInfo, 'attorney'));
            em.setFileAttachments(new List<Messaging.EmailFileAttachment>{ icsAttachment(ics, method) });
            em.setSaveAsActivity(false);
            emails.add(em);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Confirmation email failed: ' + ex.getMessage());
            }
        }
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
        User attorney,
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
        String greeting = recipient == 'client' ? 'Hi ' + clientFirst + ',' : 'Hi ' + attorney.Name.split(' ')[0] + ',';

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
            tableRow('Attorney', attorney.Name) +
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

    // ── Utility: send a standalone .ics email ─────────────────────
    private static void sendIcsEmail(
        List<String> toAddresses,
        String subject,
        String htmlBody,
        String ics,
        String method
    ) {
        Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
        em.setToAddresses(toAddresses);
        em.setSubject(subject);
        em.setHtmlBody(htmlBody);
        em.setFileAttachments(new List<Messaging.EmailFileAttachment>{ icsAttachment(ics, method) });
        em.setSaveAsActivity(false);
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ em });
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'ICS email failed: ' + ex.getMessage());
        }
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
    private static ConsultationDTO toDTO(Consultation__c c) {
        ConsultationDTO d = new ConsultationDTO();
        d.id = c.Id;
        d.consultationType = c.Type__c;
        d.status = c.Status__c;
        d.attorneyId = c.Attorney__c;
        d.attorneyName = c.Attorney__r?.Name;
        d.attorneyPhoto = c.Attorney__r?.SmallPhotoUrl;
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