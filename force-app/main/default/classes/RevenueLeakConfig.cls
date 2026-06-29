/**
 * Accessor for the protected hierarchy custom setting Revenue_Leak_Config__c.
 * Centralizes the owner-recipient, model, and email-toggle resolution so the rest
 * of the pipeline never touches the custom setting directly.
 */
public with sharing class RevenueLeakConfig {

    private static Revenue_Leak_Config__c cfg() {
        Revenue_Leak_Config__c c = Revenue_Leak_Config__c.getInstance();
        return c == null ? new Revenue_Leak_Config__c() : c;
    }

    /** Anthropic model id for narration; defaults when the setting is blank. */
    public static String model() {
        String m = cfg().Model__c;
        return String.isBlank(m) ? AnthropicCalloutService.DEFAULT_MODEL : m;
    }

    /** Firm-owner recipient for alerts; defaults to the running user when unset/invalid. */
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

    /** Whether to also email the digest (in addition to the in-app bell). */
    public static Boolean sendEmail() {
        return cfg().Send_Email__c == true;
    }
}