public without sharing class IntakeNotificationService {
    private static final String ASSIGNMENT_NOTIF_API = 'Intake_Assignment';

    // ── In-app: Intake assigned to a user ─────────────────────────
    public static void notifyAssignment(List<Intake__c> newList, Map<Id, Intake__c> oldMap) {
        List<CustomNotificationType> types = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :ASSIGNMENT_NOTIF_API
            LIMIT 1
        ];
        // Notification type not configured — fail gracefully, don't throw
        if (types.isEmpty())
            return;

        Id notifTypeId = types[0].Id;

        for (Intake__c intake : newList) {
            // Only notify real users — never queues
            if (intake.OwnerId == null)
                continue;
            if (intake.OwnerId.getSObjectType() != Schema.User.SObjectType)
                continue;

            // On update: only fire when owner actually changed
            if (oldMap != null && oldMap.get(intake.Id).OwnerId == intake.OwnerId)
                continue;

            try {
                Messaging.CustomNotification notif = new Messaging.CustomNotification();
                notif.setNotificationTypeId(notifTypeId);
                notif.setTargetId(intake.Id); // tapping opens the Intake record
                notif.setTitle('New Intake Assigned');
                notif.setBody(intake.Intake_Title__c + ' has been assigned to you for intake processing.');
                notif.send(new Set<String>{ String.valueOf(intake.OwnerId) });
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Assignment notification failed [' + intake.Id + ']: ' + e.getMessage()
                );
            }
        }
    }

    // ── Email: Status changed to Retainer Agreement Signed ───────────────────
    public static void notifyRetainerSigned(List<Intake__c> newList, Map<Id, Intake__c> oldMap) {
        List<Intake__c> signed = new List<Intake__c>();
        Set<Id> intakeIds = new Set<Id>();
        Set<Id> ownerIds = new Set<Id>();

        for (Intake__c i : newList) {
            if (i.Status__c != 'Retainer Agreement Signed')
                continue;
            if (oldMap.get(i.Id).Status__c == 'Retainer Agreement Signed')
                continue; // already signed

            signed.add(i);
            intakeIds.add(i.Id);
            if (i.OwnerId != null && i.OwnerId.getSObjectType() == Schema.User.SObjectType) {
                ownerIds.add(i.OwnerId);
            }
        }
        if (signed.isEmpty() || ownerIds.isEmpty())
            return;

        // Re-query for client name — not in Trigger.new relationship fields
        Map<Id, Intake__c> withClient = new Map<Id, Intake__c>(
            [
                SELECT Id, Name, Client__r.Name
                FROM Intake__c
                WHERE Id IN :intakeIds
            ]
        );

        Map<Id, User> owners = new Map<Id, User>(
            [
                SELECT Id, Name, Email
                FROM User
                WHERE Id IN :ownerIds AND Email != NULL
            ]
        );

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Intake__c i : signed) {
            User owner = owners.get(i.OwnerId);
            if (owner == null)
                continue;

            Intake__c full = withClient.get(i.Id);
            String clientName = (full?.Client__r?.Name != null) ? full.Client__r.Name : 'Unknown Client';

            Messaging.SingleEmailMessage em = new Messaging.SingleEmailMessage();
            em.setToAddresses(new List<String>{ owner.Email });
            em.setSubject('✅ Retainer Agreement Signed — ' + i.Intake_Title__c + ' · ' + clientName);
            em.setHtmlBody(retainerSignedBody(owner.Name, i.Intake_Title__c, clientName));
            em.setSaveAsActivity(false);
            emails.add(em);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Retainer agreement signed email failed: ' + e.getMessage());
            }
        }
    }

    // ── Email bodies ───────────────────────────────────────────────
    private static String retainerSignedBody(String ownerName, String intakeName, String clientName) {
        return '<!DOCTYPE html><html><body>' +
            '<div style="font-family:Helvetica Neue,Helvetica,Arial,sans-serif;' +
            'max-width:600px;margin:0 auto;border:1px solid #e0e5ee;' +
            'border-radius:8px;overflow:hidden;">' +
            '<div style="background:#04152f;padding:20px 28px;">' +
            '<p style="color:#fff;font-size:18px;font-weight:700;margin:0;">' +
            'Delipat Law Group</p>' +
            '<p style="color:#a8bfd6;font-size:11px;margin:4px 0 0;' +
            'text-transform:uppercase;letter-spacing:0.08em;">' +
            'Case Management Platform</p>' +
            '</div>' +
            '<div style="background:#e8f5e9;border-left:4px solid #2e7d32;' +
            'padding:14px 20px;">' +
            '<p style="color:#1b5e20;font-weight:700;margin:0;font-size:15px;">' +
            '✅ Retainer Agreement — Signed</p>' +
            '</div>' +
            '<div style="padding:28px;background:#fff;">' +
            '<p style="color:#333;font-size:14px;margin:0 0 16px;">' +
            'Hi ' +
            ownerName +
            ',</p>' +
            '<p style="color:#333;font-size:14px;margin:0 0 20px;">' +
            'The retainer agreement below has been signed. ' +
            'The matter is now active — please proceed with next steps.</p>' +
            '<table style="width:100%;border-collapse:collapse;font-size:13px;">' +
            '<tr><td style="padding:10px 14px;background:#f4f6f9;color:#777;' +
            'font-size:11px;text-transform:uppercase;letter-spacing:0.05em;' +
            'width:35%;">Intake No.</td>' +
            '<td style="padding:10px 14px;font-weight:700;color:#04152f;">' +
            intakeName +
            '</td></tr>' +
            '<tr><td style="padding:10px 14px;background:#f4f6f9;color:#777;' +
            'font-size:11px;text-transform:uppercase;letter-spacing:0.05em;">' +
            'Client</td>' +
            '<td style="padding:10px 14px;font-weight:700;color:#04152f;">' +
            clientName +
            '</td></tr>' +
            '</table>' +
            '</div>' +
            '<div style="padding:16px 28px;background:#f8f9fb;' +
            'border-top:1px solid #e0e5ee;">' +
            '<p style="color:#aaa;font-size:11px;margin:0;">' +
            'Delipat PI Platform · Automated Notification · Do not reply</p>' +
            '</div>' +
            '</div></body></html>';
    }
}
