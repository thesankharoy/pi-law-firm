public without sharing class FollowUpEndOfDayService {
    // ── 1. Mark today's (and any missed) follow-up tasks Incomplete ─
    // Runs first so emailPendingFollowUps picks up the freshly marked rows.
    public static void markIncomplete() {
        List<Task> overdue = [
            SELECT Id
            FROM Task
            WHERE ActivityDate <= :Date.today() AND Status = 'Not Started' AND Subject LIKE 'Day %' AND WhatId != NULL
        ];
        if (overdue.isEmpty())
            return;

        for (Task t : overdue)
            t.Status = 'Incomplete';

        try {
            update overdue;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'markIncomplete failed: ' + e.getMessage());
        }
    }

    // ── 2. Email each owner a summary of their incomplete tasks ─────
    // Called after markIncomplete so the query captures the full picture.
    public static void emailPendingFollowUps() {
        List<Task> incomplete = [
            SELECT Id, Subject, ActivityDate, Status, OwnerId, What.Name
            FROM Task
            WHERE ActivityDate <= :Date.today() AND Status = 'Incomplete' AND Subject LIKE 'Day %' AND WhatId != NULL
            ORDER BY OwnerId, ActivityDate ASC
        ];
        if (incomplete.isEmpty())
            return;

        // Group by owner
        Map<Id, List<Task>> byOwner = new Map<Id, List<Task>>();
        for (Task t : incomplete) {
            if (!byOwner.containsKey(t.OwnerId)) {
                byOwner.put(t.OwnerId, new List<Task>());
            }
            byOwner.get(t.OwnerId).add(t);
        }

        // Filter to user owners only — tasks can't be queue-owned but be safe
        Set<Id> userOwnerIds = new Set<Id>();
        for (Id oid : byOwner.keySet()) {
            if (oid != null && oid.getSObjectType() == Schema.User.SObjectType) {
                userOwnerIds.add(oid);
            }
        }
        if (userOwnerIds.isEmpty())
            return;

        Map<Id, User> owners = new Map<Id, User>(
            [
                SELECT Id, Name, Email
                FROM User
                WHERE Id IN :userOwnerIds AND Email != NULL
            ]
        );

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id ownerId : userOwnerIds) {
            User owner = owners.get(ownerId);
            if (owner == null || String.isBlank(owner.Email))
                continue;

            List<Task> tasks = byOwner.get(ownerId);

            Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
            em.setToAddresses(new List<String>{ owner.Email });
            em.setSubject('⚠️ ' + tasks.size() + ' Incomplete Follow-Up Task(s) — ' + Date.today().format());
            em.setHtmlBody(pendingTasksBody(owner.Name, tasks));
            em.setSaveAsActivity(false);
            emails.add(em);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Pending tasks email failed: ' + e.getMessage());
            }
        }
    }

    private static String pendingTasksBody(String ownerName, List<Task> tasks) {
        String rows = '';
        for (Task t : tasks) {
            String badge = t.ActivityDate < Date.today()
                ? '<span style="background:#fde8ec;color:#b3123c;padding:2px 8px;' +
                  'border-radius:10px;font-size:11px;font-weight:700;">Overdue</span>'
                : '<span style="background:#fff3cd;color:#856404;padding:2px 8px;' +
                  'border-radius:10px;font-size:11px;font-weight:700;">Due Today</span>';

            rows +=
                '<tr>' +
                '<td style="padding:10px 12px;border-bottom:1px solid #e0e5ee;' +
                'font-size:13px;color:#1a1a1a;">' +
                t.Subject +
                '</td>' +
                '<td style="padding:10px 12px;border-bottom:1px solid #e0e5ee;' +
                'font-size:13px;color:#555;">' +
                (t.What != null ? t.What.Name : '—') +
                '</td>' +
                '<td style="padding:10px 12px;border-bottom:1px solid #e0e5ee;' +
                'font-size:12px;color:#888;">' +
                t.ActivityDate.format() +
                '</td>' +
                '<td style="padding:10px 12px;border-bottom:1px solid #e0e5ee;">' +
                badge +
                '</td>' +
                '</tr>';
        }

        return '<!DOCTYPE html><html><body>' +
            '<div style="font-family:Helvetica Neue,Helvetica,Arial,sans-serif;' +
            'max-width:640px;margin:0 auto;border:1px solid #e0e5ee;' +
            'border-radius:8px;overflow:hidden;">' +
            '<div style="background:#04152f;padding:20px 28px;">' +
            '<p style="color:#fff;font-size:18px;font-weight:700;margin:0;">' +
            'Delipat Law Group</p>' +
            '<p style="color:#a8bfd6;font-size:11px;margin:4px 0 0;' +
            'text-transform:uppercase;letter-spacing:0.08em;">' +
            'Daily Follow-Up Summary · ' +
            Date.today().format() +
            '</p>' +
            '</div>' +
            '<div style="background:#fff3cd;border-left:4px solid #f9a825;' +
            'padding:14px 20px;">' +
            '<p style="color:#e65100;font-weight:700;margin:0;font-size:15px;">' +
            '⚠️ ' +
            tasks.size() +
            ' incomplete follow-up task(s) require your attention</p>' +
            '</div>' +
            '<div style="padding:28px;background:#fff;">' +
            '<p style="color:#333;font-size:14px;margin:0 0 16px;">' +
            'Hi ' +
            ownerName +
            ',</p>' +
            '<p style="color:#333;font-size:14px;margin:0 0 20px;">' +
            'The following follow-up tasks were not completed. ' +
            'Please action them as soon as possible to stay on top of your leads.</p>' +
            '<table style="width:100%;border-collapse:collapse;">' +
            '<tr style="background:#04152f;">' +
            '<th style="padding:10px 12px;color:#fff;font-size:11px;text-align:left;' +
            'text-transform:uppercase;letter-spacing:0.06em;">Task</th>' +
            '<th style="padding:10px 12px;color:#fff;font-size:11px;text-align:left;' +
            'text-transform:uppercase;letter-spacing:0.06em;">Intake</th>' +
            '<th style="padding:10px 12px;color:#fff;font-size:11px;text-align:left;' +
            'text-transform:uppercase;letter-spacing:0.06em;">Due Date</th>' +
            '<th style="padding:10px 12px;color:#fff;font-size:11px;text-align:left;' +
            'text-transform:uppercase;letter-spacing:0.06em;">Status</th>' +
            '</tr>' +
            rows +
            '</table>' +
            '<p style="color:#555;font-size:13px;margin:20px 0 0;">' +
            'Log in to Salesforce to view and complete these tasks.</p>' +
            '</div>' +
            '<div style="padding:16px 28px;background:#f8f9fb;' +
            'border-top:1px solid #e0e5ee;">' +
            '<p style="color:#aaa;font-size:11px;margin:0;">' +
            'Delipat PI Platform · Automated Notification · Do not reply</p>' +
            '</div>' +
            '</div></body></html>';
    }
}