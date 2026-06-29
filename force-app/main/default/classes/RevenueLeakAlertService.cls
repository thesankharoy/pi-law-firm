/**
 * Delivers a narrated digest to the firm owner: writes a Leak_Alert__c record (so the
 * AI output is queryable/reportable), fires an in-app bell notification, optionally
 * emails the owner, and flips each leak to Alerted so the next run never re-pushes it.
 */
public with sharing class RevenueLeakAlertService {

    private static final String NOTIF_TYPE = 'Revenue_Leak_Alert';

    public static Leak_Alert__c deliver(RevenueLeakNarrationService.NarrationResult n) {
        if (n == null || n.leaks == null || n.leaks.isEmpty()) {
            return null;
        }
        Id ownerId = RevenueLeakConfig.ownerUserId();

        Leak_Alert__c alert = new Leak_Alert__c(
            Owner_User__c = ownerId,
            Leak_Count__c = n.leaks.size(),
            Total_Value__c = n.totalValue,
            Narrative__c = n.narrative,
            Narrative_Source__c = n.source,
            Model__c = n.model,
            Input_Tokens__c = n.inputTokens,
            Output_Tokens__c = n.outputTokens,
            Delivered_At__c = System.now()
        );
        insert alert;

        for (Revenue_Leak__c l : n.leaks) {
            l.Status__c = 'Alerted';
            l.Alerted__c = true;
            l.Alert__c = alert.Id;
        }
        update n.leaks;

        sendBell(ownerId, alert, n);
        if (RevenueLeakConfig.sendEmail()) {
            sendEmail(ownerId, alert, n);
        }
        return alert;
    }

    // ── In-app bell ──────────────────────────────────────────────────
    private static void sendBell(Id ownerId, Leak_Alert__c alert, RevenueLeakNarrationService.NarrationResult n) {
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIF_TYPE LIMIT 1
        ];
        if (types.isEmpty()) return;

        Messaging.CustomNotification cn = new Messaging.CustomNotification();
        cn.setTitle('Revenue Leak Alert: ' + n.leaks.size() + ' open leak(s)');
        cn.setBody('Approx. $' + money(n.totalValue) + ' at risk. Tap to review.');
        cn.setNotificationTypeId(types[0].Id);
        cn.setTargetId(alert.Id);
        try {
            cn.send(new Set<String>{ String.valueOf(ownerId) });
        } catch (Exception e) {
            // Never let a notification-delivery hiccup undo the alert record/leak flip.
        }
    }

    // ── Email ────────────────────────────────────────────────────────
    private static void sendEmail(Id ownerId, Leak_Alert__c alert, RevenueLeakNarrationService.NarrationResult n) {
        List<User> owners = [SELECT Email FROM User WHERE Id = :ownerId AND Email != null LIMIT 1];
        if (owners.isEmpty()) return;

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ owners[0].Email });
        msg.setSubject('Revenue Leak Alert — $' + money(n.totalValue) + ' at risk');
        msg.setPlainTextBody(n.narrative);
        msg.setSaveAsActivity(false);
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
        } catch (Exception e) {
            // Email is best-effort; the bell + record are the source of truth.
        }
    }

    private static String money(Decimal d) {
        return (d == null ? 0 : d).setScale(0, System.RoundingMode.HALF_UP).format();
    }
}