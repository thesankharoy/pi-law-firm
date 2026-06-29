/**
 * Fires the conversational SMS intake bot when a new inbound text lands.
 * After-insert only, so the bot's own outbound replies (and our Intake__c
 * linking updates) never re-trigger it.
 */
trigger TwilioSF_Message_SmsBot on TwilioSF__Message__c (after insert) {
    SmsIntakeBotService.handleInbound(Trigger.new);
}