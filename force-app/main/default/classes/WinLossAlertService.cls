/**
 * Persists the narrated digest as Loss_Insight__c and pushes it to the firm owner via the
 * Win_Loss_Insight custom notification (and optional email).
 */
public with sharing class WinLossAlertService {

    private static final String NOTIF_TYPE = 'Win_Loss_Insight';

    public static Loss_Insight__c deliver(
        LossNarrationService.NarrationResult n, LossAggregationService.Aggregates a
    ) {
        Id ownerId = WinLossConfig.ownerUserId();

        Loss_Insight__c ins = new Loss_Insight__c(
            Owner_User__c = ownerId,
            Narrative__c = n.narrative,
            Narrative_Source__c = n.source,
            Model__c = n.model,
            Input_Tokens__c = n.inputTokens,
            Output_Tokens__c = n.outputTokens,
            Total_Losses__c = a.total,
            Process_Count__c = a.processCount,
            Lookback_Days__c = a.lookbackDays,
            Delivered_At__c = System.now()
        );
        insert ins;

        sendBell(ownerId, ins, a);
        if (WinLossConfig.sendEmail()) {
            sendEmail(ownerId, ins, n);
        }
        return ins;
    }

    private static void sendBell(Id ownerId, Loss_Insight__c ins, LossAggregationService.Aggregates a) {
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIF_TYPE LIMIT 1
        ];
        if (types.isEmpty()) return;

        Messaging.CustomNotification cn = new Messaging.CustomNotification();
        cn.setTitle('Win/Loss: ' + a.total + ' losses analyzed');
        cn.setBody(a.processCount + ' were fixable (Process). Tap to review.');
        cn.setNotificationTypeId(types[0].Id);
        cn.setTargetId(ins.Id);
        try {
            cn.send(new Set<String>{ String.valueOf(ownerId) });
        } catch (Exception e) {
            // never let a notification hiccup undo the insight record
        }
    }

    private static void sendEmail(Id ownerId, Loss_Insight__c ins, LossNarrationService.NarrationResult n) {
        List<User> owners = [SELECT Email FROM User WHERE Id = :ownerId AND Email != null LIMIT 1];
        if (owners.isEmpty()) return;

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ owners[0].Email });
        msg.setSubject('Win/Loss digest — ' + n.processCount + ' fixable of ' + n.total + ' losses');
        msg.setPlainTextBody(n.narrative);
        msg.setSaveAsActivity(false);
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
        } catch (Exception e) {
            // email is best-effort
        }
    }
}