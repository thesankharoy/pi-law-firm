/**
 * Thin controller for the `intakeMessenger` LWC. Delegates to
 * IntakeMessagingService (thin controller -> service pattern).
 */
public with sharing class IntakeMessagingController {

    @AuraEnabled
    public static IntakeMessagingService.Conversation getConversation(Id intakeId) {
        try {
            return IntakeMessagingService.getConversation(intakeId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static IntakeMessagingService.Conversation sendReply(Id intakeId, String body) {
        try {
            return IntakeMessagingService.sendReply(intakeId, body);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}