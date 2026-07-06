public without sharing class ReferralAgreementController {

    // Exposed to VF page
    public String firmName       { get; private set; }
    public String firmAddress    { get; private set; }
    public String firmPhone      { get; private set; }
    public String clientFullName { get; private set; }
    public String clientPhone    { get; private set; }
    public String clientEmail    { get; private set; }
    public String intakeName     { get; private set; }
    public String incidentType   { get; private set; }
    public String incidentDate   { get; private set; }
    public String incidentLocation { get; private set; }
    public String referralReason { get; private set; }
    public String agreementDate  { get; private set; }

    public ReferralAgreementController(ApexPages.StandardController sc) {
        Intake__c rec = (Intake__c) sc.getRecord();

        Intake__c intake = [
            SELECT
                Id, Name, Status__c,
                Client__c,
                Client__r.Name, Client__r.Email, Client__r.Phone,
                Incident_Type__c, Incident_Date__c,
                Incident_Location__Street__s,
                Incident_Location__City__s,
                Incident_Location__StateCode__s,
                Incident_Location__PostalCode__s,
                Incident_Location__CountryCode__s,
                Referral_Reason__c          
            FROM Intake__c
            WHERE Id = :rec.Id
            LIMIT 1
        ];

        // Firm info from Organization
        Organization org = [SELECT Name, Street, City, State, PostalCode, Phone FROM Organization LIMIT 1];
        this.firmName    = org.Name;
        this.firmPhone   = org.Phone != null ? org.Phone : '';

        List<String> addrParts = new List<String>();
        if (String.isNotBlank(org.Street))     addrParts.add(org.Street);
        if (String.isNotBlank(org.City))       addrParts.add(org.City);
        if (String.isNotBlank(org.State))      addrParts.add(org.State);
        if (String.isNotBlank(org.PostalCode)) addrParts.add(org.PostalCode);
        this.firmAddress = String.join(addrParts, ', ');

        // Client
        this.clientFullName = intake.Client__r != null ? intake.Client__r.Name  : '';
        this.clientPhone    = intake.Client__r != null ? intake.Client__r.Phone : '';
        this.clientEmail    = intake.Client__r != null ? intake.Client__r.Email : '';

        // Intake
        this.intakeName  = intake.Name;
        this.incidentType = intake.Incident_Type__c != null ? intake.Incident_Type__c : '';
        this.incidentDate = intake.Incident_Date__c != null ? intake.Incident_Date__c.format() : '';

        List<String> locParts = new List<String>();
        if (String.isNotBlank(intake.Incident_Location__Street__s))   locParts.add(intake.Incident_Location__Street__s);
        if (String.isNotBlank(intake.Incident_Location__City__s))     locParts.add(intake.Incident_Location__City__s);
        if (String.isNotBlank(intake.Incident_Location__StateCode__s)) locParts.add(intake.Incident_Location__StateCode__s);
        if (String.isNotBlank(intake.Incident_Location__PostalCode__s)) locParts.add(intake.Incident_Location__PostalCode__s);
        this.incidentLocation = String.join(locParts, ', ');

        // Referral reason — if you don't have this field yet, just hardcode or leave blank
        try {
            this.referralReason = intake.get('Referral_Reason__c') != null
                ? String.valueOf(intake.get('Referral_Reason__c'))
                : 'Unable to represent at this time';
        } catch (Exception e) {
            this.referralReason = 'Unable to represent at this time';
        }

        this.agreementDate = Date.today().format();
    }
}