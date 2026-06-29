public with sharing class IntakeDocumentDataService {

    public class IntakeDocPacket {

    // Case / Intake
    public Id intakeId { get; set; }
    public String intakeNumber { get; set; }
    public String caseType { get; set; }
    public Date incidentDate { get; set; }
    public Date statuteOfLimitations { get; set; }

    // Client
    public Id clientId { get; set; }
    public String clientFullName { get; set; }
    public String clientFirstName { get; set; }
    public String clientLastName { get; set; }
    public Date clientDob { get; set; }
    public String clientAddressLine { get; set; }
    public String clientCity { get; set; }
    public String clientState { get; set; }
    public String clientPostalCode { get; set; }
    public String clientPhone { get; set; }
    public String clientEmail { get; set; }

    // Attorney
    public String attorneyName { get; set; }
    public String firmName { get; set; }

    // Dates
    public Date today { get; set; }

    public Boolean isValid() {
        return clientFullName != null && intakeNumber != null;
    }
}

    // Firm name is not on any object in the provided schema; centralised
    // here as a single constant so it's a one-line change if/when a
    // Firm Settings custom setting / metadata type is introduced.
    private static final String FIRM_NAME = 'Delipat Law Group';

    public static IntakeDocPacket buildPacket(Id intakeId) {
        IntakeDocPacket packet = new IntakeDocPacket();
        packet.today = Date.today();
        packet.firmName = FIRM_NAME;

        Intake__c intake = [
            SELECT Id, Name, Incident_Type__c, Incident_Date__c,
                   Statute_of_Limitations__c, Client__c
            FROM Intake__c
            WHERE Id = :intakeId
            LIMIT 1
        ];

        packet.intakeId = intake.Id;
        packet.intakeNumber = intake.Name;
        packet.caseType = intake.Incident_Type__c;
        packet.incidentDate = intake.Incident_Date__c;
        packet.statuteOfLimitations = intake.Statute_of_Limitations__c;

        if (intake.Client__c != null) {
            populateClient(packet, intake.Client__c);
        }

        populateAttorney(packet, intake.Id);

        return packet;
    }

    private static void populateClient(IntakeDocPacket packet, Id clientPartyId) {
        // Client__c on Intake__c is a Lookup(Party). Party maps to the
        // standard Contact object's record-driven fields in this schema
        // (Name, MailingAddress, Phone, Email, Birthdate all appear on the
        // Contact field list supplied).
        for (Contact c : [
            SELECT Id, FirstName, LastName, Name, Birthdate,
                   MailingStreet, MailingCity, MailingState, MailingPostalCode,
                   Phone, MobilePhone, Email
            FROM Contact
            WHERE Id = :clientPartyId
            
            LIMIT 1
        ]) {
            packet.clientId = c.Id;
            packet.clientFirstName = c.FirstName;
            packet.clientLastName = c.LastName;
            packet.clientFullName = c.Name;
            packet.clientDob = c.Birthdate;
            packet.clientAddressLine = c.MailingStreet;
            packet.clientCity = c.MailingCity;
            packet.clientState = c.MailingState;
            packet.clientPostalCode = c.MailingPostalCode;
            packet.clientPhone = (c.Phone != null) ? c.Phone : c.MobilePhone;
            packet.clientEmail = c.Email;
        }
    }

    private static void populateAttorney(IntakeDocPacket packet, Id intakeId) {
        // Role__c links Party <-> Intake with a Role__c picklist.
        // Looked up via Intake only — Matter is intentionally out of scope
        // for this feature.
        if (intakeId == null) {
            return;
        }

        List<Role__c> roles = [
            SELECT Id, Party__c, Party__r.Name, Role__c
            FROM Role__c
            WHERE Intake__c = :intakeId
              AND Role__c = 'Attorney'
            LIMIT 1
        ];

        if (!roles.isEmpty()) {
            packet.attorneyName = roles[0].Party__r.Name;
        }
    }
}