/**
 * Accessor for the protected hierarchy custom setting Win_Loss_Config__c.
 * Centralizes model, owner, batch scope, lookback, confidence threshold, and email toggle.
 */
public with sharing class WinLossConfig {

    private static Win_Loss_Config__c cfg() {
        Win_Loss_Config__c c = Win_Loss_Config__c.getInstance();
        return c == null ? new Win_Loss_Config__c() : c;
    }

    public static String model() {
        String m = cfg().Model__c;
        return String.isBlank(m) ? AnthropicCalloutService.DEFAULT_MODEL : m;
    }

    public static Id ownerUserId() {
        String raw = cfg().Owner_User_Id__c;
        if (String.isBlank(raw)) {
            return UserInfo.getUserId();
        }
        try {
            return (Id) raw.trim();
        } catch (Exception e) {
            return UserInfo.getUserId();
        }
    }

    public static Integer batchScope() {
        Decimal s = cfg().Batch_Scope__c;
        return (s == null || s < 1) ? 5 : s.intValue();
    }

    public static Integer lookbackDays() {
        Decimal d = cfg().Lookback_Days__c;
        return (d == null || d < 1) ? 90 : d.intValue();
    }

    public static Decimal confidenceThreshold() {
        Decimal c = cfg().Confidence_Threshold__c;
        return c == null ? 0.55 : c;
    }

    public static Boolean sendEmail() {
        return cfg().Send_Email__c == true;
    }
}