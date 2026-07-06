/**
 * Backing service for the custom SMS conversation panel (`intakeMessenger` LWC)
 * that replaces the TwilioSF managed-package "Message Board" widget.
 *
 * Messages still live in TwilioSF__Message__c (the package logs + delivers them);
 * this service just reads a single lead's thread for an Intake and sends a
 * specialist reply. A reply is inserted as an 'outbound-reply' message, which:
 *   1) is transmitted by the TwilioSF package on insert (same path the bot uses), and
 *   2) is the exact human-handoff signal SmsIntakeBotService watches for, so the
 *      AI intake bot automatically stands down the moment a specialist replies.
 */
public with sharing class IntakeMessagingService {

    // ---- DTOs returned to the LWC ------------------------------------------

    public class Conversation {
        @AuraEnabled public String leadPhone;      // number the client texts from (E.164)
        @AuraEnabled public String firmNumber;     // intake number replies are sent from
        @AuraEnabled public String clientName;     // display name for inbound bubbles
        @AuraEnabled public Boolean canReply;      // false when we have no number to text
        @AuraEnabled public Boolean botActive;     // true until a specialist has replied
        @AuraEnabled public List<Msg> messages = new List<Msg>();
    }

    public class Msg {
        @AuraEnabled public Id id;
        @AuraEnabled public String body;
        @AuraEnabled public Datetime sentAt;
        @AuraEnabled public Boolean outbound;      // true = from the firm, false = from the client
        @AuraEnabled public Boolean fromBot;       // outbound message authored by the AI bot
    }

    // ---- Read ---------------------------------------------------------------

    public static Conversation getConversation(Id intakeId) {
        Conversation c = new Conversation();
        if (intakeId == null) return c;

        // Candidate lead number from the Intake (used to gather the thread even
        // before any message is linked to the Intake).
        Intake__c intake = [
            SELECT Id, Client__c, Client__r.Name, Client__r.MobilePhone, Client__r.Phone,
                   Intake_Phone__c
            FROM Intake__c WHERE Id = :intakeId LIMIT 1
        ];
        c.clientName = (intake.Client__r != null && intake.Client__r.Name != null)
            ? intake.Client__r.Name : 'Client';

        String candidate = firstNonBlank(new List<String>{
            intake.Intake_Phone__c,
            intake.Client__r != null ? intake.Client__r.MobilePhone : null,
            intake.Client__r != null ? intake.Client__r.Phone : null
        });
        String last10 = last10(candidate);
        String pat = (last10 != null) ? '%' + last10 : ' ';   // unmatchable when no number

        List<TwilioSF__Message__c> rows = [
            SELECT Id, TwilioSF__Direction__c, TwilioSF__Body__c, TwilioSF__Date_Created__c,
                   TwilioSF__From_Number__c, TwilioSF__To_Number__c
            FROM TwilioSF__Message__c
            WHERE Intake__c = :intakeId
               OR TwilioSF__From_Number__c LIKE :pat
               OR TwilioSF__To_Number__c LIKE :pat
            ORDER BY TwilioSF__Date_Created__c ASC
            LIMIT 500
        ];

        String leadPhone = candidate;
        String firmNumber = null;
        Boolean sawReply = false;

        for (TwilioSF__Message__c m : rows) {
            if (String.isBlank(m.TwilioSF__Body__c)) continue;
            String dir = m.TwilioSF__Direction__c;
            Boolean outbound = dir != null && dir.startsWith('outbound');

            Msg msg = new Msg();
            msg.id = m.Id;
            msg.body = m.TwilioSF__Body__c;
            msg.sentAt = m.TwilioSF__Date_Created__c;
            msg.outbound = outbound;
            msg.fromBot = (dir == 'outbound-api');   // bot sends outbound-api; specialists send outbound-reply
            c.messages.add(msg);

            // Derive the real numbers from the actual traffic (most reliable).
            if (!outbound) {
                if (String.isNotBlank(m.TwilioSF__From_Number__c)) leadPhone = m.TwilioSF__From_Number__c;
                if (String.isNotBlank(m.TwilioSF__To_Number__c)) firmNumber = m.TwilioSF__To_Number__c;
            }
            if (dir == 'outbound-reply') sawReply = true;
        }

        // Fallback firm number = the configured intake number.
        if (String.isBlank(firmNumber)) {
            SMS_Bot_Config__c cfg = SMS_Bot_Config__c.getOrgDefaults();
            firmNumber = (cfg != null) ? cfg.Intake_From_Number__c : null;
        }

        c.leadPhone = leadPhone;
        c.firmNumber = firmNumber;
        c.canReply = String.isNotBlank(leadPhone) && String.isNotBlank(firmNumber);
        c.botActive = !sawReply;
        return c;
    }

    // ---- Send ---------------------------------------------------------------

    public static Conversation sendReply(Id intakeId, String body) {
        if (String.isBlank(body)) {
            throw new AuraHandledException('Message is empty.');
        }
        Conversation c = getConversation(intakeId);
        if (!c.canReply) {
            throw new AuraHandledException('No phone number on file for this lead — can\'t send a text.');
        }

        Intake__c intake = [SELECT Client__c FROM Intake__c WHERE Id = :intakeId LIMIT 1];

        insert new TwilioSF__Message__c(
            TwilioSF__Direction__c   = 'outbound-reply',   // delivers + stands the AI bot down
            TwilioSF__From_Number__c = c.firmNumber,
            TwilioSF__To_Number__c   = c.leadPhone,
            TwilioSF__Body__c        = body.trim(),
            TwilioSF__Contact__c     = intake.Client__c,
            Intake__c                = intakeId
        );

        return getConversation(intakeId);
    }

    // ---- helpers ------------------------------------------------------------

    private static String firstNonBlank(List<String> vals) {
        for (String v : vals) {
            if (String.isNotBlank(v)) return v;
        }
        return null;
    }

    private static String last10(String phone) {
        if (String.isBlank(phone)) return null;
        String digits = phone.replaceAll('[^0-9]', '');
        if (digits.length() < 7) return null;
        return digits.length() >= 10 ? digits.substring(digits.length() - 10) : digits;
    }
}