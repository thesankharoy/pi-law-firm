public without sharing class RetainerAgreementController {
    // ── Firm (from Salesforce Organization object) ─────────────────
    public String firmName { get; private set; }
    public String firmAddress { get; private set; }
    public String firmPhone { get; private set; }
    public String firmEmail { get; private set; }
    public String firmBarNumber { get; private set; }

    // Attorney (from Role__c — Role = 'Attorney', Role_Sub_Category__c = 'Lead Attorney')
    public String attorneyName { get; private set; }
    public String attorneyBarNumber { get; private set; }
    public String attorneySignatureURL { get; private set; }

    // Opposing party (from Role__c — Role = 'Opposing Party')
    public String opposingParty { get; private set; }
    public String opposingInsurance { get; private set; }

    // ── Client ────────────────────────────────────────────────────
    public String clientFullName { get; private set; }
    public String clientAddress { get; private set; }
    public String clientPhone { get; private set; }
    public String clientEmail { get; private set; }
    public String clientDOB { get; private set; }
    public String clientStreet { get; private set; }
    public String clientCity { get; private set; }
    public String clientState { get; private set; }
    public String clientPostalCode { get; private set; }
    public String clientCountry { get; private set; }
    public String clientSignatureURL { get; private set; }

    // ── Incident / Matter ─────────────────────────────────────────
    public String incidentType { get; private set; }
    public String incidentDate { get; private set; }
    public String incidentLocation { get; private set; }
    public String incidentStreet { get; private set; }
    public String incidentCity { get; private set; }
    public String incidentState { get; private set; }
    public String incidentPostalCode { get; private set; }
    public String incidentCountry { get; private set; }

    // ── Document meta ─────────────────────────────────────────────
    public String retainerDate { get; private set; }
    public String retainerRefNumber { get; private set; }

    // ── Fee ───────────────────────────────────────────────────────
    public String contingencyPercent { get; private set; }
    public String contingencyPercentTrial { get; private set; }

    // ── E-sign (placeholder — wire DocuSign / HelloSign later) ────
    public Boolean isSigned { get; private set; }
    public String signedDate { get; private set; }
    public String signerIpAddress { get; private set; }
    public String documentHash { get; private set; }
    public String eSignProvider { get; private set; }

    public RetainerAgreementController(ApexPages.StandardController sc) {
        // ── 1. Intake + Client ───────────────────────────────────
        Intake__c intake = [
            SELECT
                Id,
                Name,
                Incident_Type__c,
                Incident_Location__Street__s,
                Incident_Location__City__s,
                Incident_Location__StateCode__s,
                Incident_Location__PostalCode__s,
                Incident_Location__CountryCode__s,
                Incident_Date__c,
                Status__c,
                OwnerId,
                Client__c,
                Client__r.Name,
                Client__r.Email,
                Client__r.Phone,
                Client__r.MobilePhone,
                Client__r.Birthdate,
                Client__r.MailingStreet,
                Client__r.MailingCity,
                Client__r.MailingState,
                Client__r.MailingPostalCode,
                Client__r.MailingCountry
            FROM Intake__c
            WHERE Id = :sc.getId()
        ];

        // ── 2. Salesforce org (firm info) ─────────────────────────
        Organization org = [
            SELECT Name, Street, City, State, PostalCode, Country, Phone
            FROM Organization
            LIMIT 1
        ];

        // ── 3. Attorney — Role__c where Role = Attorney, Role_Sub_Category__c = Lead Attorney
        List<Role__c> attorneyRoles = [
            SELECT Party__r.Name, Party__r.Bar_Number__c
            FROM Role__c
            WHERE Intake__c = :intake.Id AND Role__c = 'Attorney' AND Role_Sub_Category__c = 'Lead Attorney'
            LIMIT 1
        ];

        // ── 4. Opposing parties from Role__c ──────────────────────
        List<Role__c> opposingRoles = [
            SELECT Party__r.Name
            FROM Role__c
            WHERE Intake__c = :intake.Id AND Role__c = 'Opposing Party'
            LIMIT 5
        ];
        List<String> oppNames = new List<String>();
        for (Role__c r : opposingRoles) {
            if (String.isNotBlank(r.Party__r.Name))
                oppNames.add(r.Party__r.Name);
        }

        // ══════════════════════════════════════════════════════════
        // FIRM
        // ══════════════════════════════════════════════════════════
        firmName = org.Name;
        firmPhone = String.isNotBlank(org.Phone) ? org.Phone : '—';
        firmEmail = UserInfo.getUserEmail();

        List<String> addrParts = new List<String>();
        if (String.isNotBlank(org.Street))
            addrParts.add(org.Street);
        if (String.isNotBlank(org.City))
            addrParts.add(org.City);
        if (String.isNotBlank(org.State))
            addrParts.add(org.State);
        if (String.isNotBlank(org.PostalCode))
            addrParts.add(org.PostalCode);
        if (String.isNotBlank(org.Country))
            addrParts.add(org.Country);
        firmAddress = addrParts.isEmpty() ? '—' : String.join(addrParts, ', ');

        // Pull bar number from Custom Setting (Setup → Custom Settings → Firm Settings)
        // Field: Bar_Number__c on Firm_Settings__c (hierarchy setting, org default)
        // If you haven't created that yet, it'll just return '—'
        // try {
        //     Firm_Settings__c fs = Firm_Settings__c.getOrgDefaults();
        //     firmBarNumber = (fs != null && String.isNotBlank(fs.Bar_Number__c)) ? fs.Bar_Number__c : '—';
        // } catch (Exception e) {
        //     firmBarNumber = '—';
        // }
        firmBarNumber = '—';

        // ══════════════════════════════════════════════════════════
        // ATTORNEY
        // ══════════════════════════════════════════════════════════
        attorneyName = attorneyRoles.isEmpty() ? '—' : attorneyRoles[0].Party__r.Name;
        attorneyBarNumber = attorneyRoles.isEmpty() ? '—' : attorneyRoles[0].Party__r.Bar_Number__c;
        attorneySignatureURL = ''; // wire to e-sign provider

        // ══════════════════════════════════════════════════════════
        // CLIENT
        // ══════════════════════════════════════════════════════════
        clientFullName = intake.Client__r.Name;

        // Phone: Phone is primary, MobilePhone is secondary
        clientPhone = String.isNotBlank(intake.Client__r.Phone)
            ? intake.Client__r.Phone
            : (String.isNotBlank(intake.Client__r.MobilePhone) ? intake.Client__r.MobilePhone : '—');

        clientEmail = String.isNotBlank(intake.Client__r.Email) ? intake.Client__r.Email : '—';

        clientDOB = intake.Client__r.Birthdate != null
            ? DateTime.newInstance(intake.Client__r.Birthdate, Time.newInstance(0, 0, 0, 0)).format('MMMM d, yyyy')
            : 'Not Provided';
        clientSignatureURL = ''; // wire to e-sign provider

        // Individual client address fields — VF renders each conditionally
        clientStreet = intake.Client__r.MailingStreet;
        clientCity = intake.Client__r.MailingCity;
        clientState = intake.Client__r.MailingState;
        clientPostalCode = intake.Client__r.MailingPostalCode;
        clientCountry = intake.Client__r.MailingCountry;

        // Flat string for any plain-text usage
        List<String> cAddrParts = new List<String>();
        if (String.isNotBlank(clientStreet))
            cAddrParts.add(clientStreet);
        if (String.isNotBlank(clientCity))
            cAddrParts.add(clientCity);
        if (String.isNotBlank(clientState))
            cAddrParts.add(clientState);
        if (String.isNotBlank(clientPostalCode))
            cAddrParts.add(clientPostalCode);
        if (String.isNotBlank(clientCountry))
            cAddrParts.add(clientCountry);
        clientAddress = cAddrParts.isEmpty() ? 'Not Provided' : String.join(cAddrParts, ', ');

        // ══════════════════════════════════════════════════════════
        // INCIDENT
        // ══════════════════════════════════════════════════════════
        incidentType = String.isNotBlank(intake.Incident_Type__c) ? intake.Incident_Type__c : 'Personal Injury';

        incidentDate = intake.Incident_Date__c != null
            ? DateTime.newInstance(intake.Incident_Date__c, Time.newInstance(0, 0, 0, 0)).format('MMMM d, yyyy')
            : 'Not Specified';

        // Incident location fields
        incidentStreet = intake.Incident_Location__Street__s;
        incidentCity = intake.Incident_Location__City__s;
        incidentState = intake.Incident_Location__StateCode__s;
        incidentPostalCode = intake.Incident_Location__PostalCode__s;
        incidentCountry = intake.Incident_Location__CountryCode__s;

        List<String> locParts = new List<String>();
        if (String.isNotBlank(incidentStreet))
            locParts.add(incidentStreet);
        if (String.isNotBlank(incidentCity))
            locParts.add(incidentCity);
        if (String.isNotBlank(incidentState))
            locParts.add(incidentState);
        if (String.isNotBlank(incidentPostalCode))
            locParts.add(incidentPostalCode);
        if (String.isNotBlank(incidentCountry))
            locParts.add(incidentCountry);
        incidentLocation = locParts.isEmpty() ? 'Not Specified' : String.join(locParts, ', ');

        opposingParty = oppNames.isEmpty() ? 'To Be Determined' : String.join(oppNames, '; ');
        opposingInsurance = 'To Be Determined'; // wire to Insurance__c object in a later stage

        // ══════════════════════════════════════════════════════════
        // DOCUMENT META
        // ══════════════════════════════════════════════════════════
        retainerDate = DateTime.now().format('MMMM d, yyyy');
        retainerRefNumber = intake.Name;

        // ══════════════════════════════════════════════════════════
        // FEES
        // ══════════════════════════════════════════════════════════
        contingencyPercent = '33.33';
        contingencyPercentTrial = '40';

        // ══════════════════════════════════════════════════════════
        // E-SIGN (placeholder — not integrated)
        // ══════════════════════════════════════════════════════════
        isSigned = false;
        signedDate = '';
        signerIpAddress = '';
        documentHash = '';
        eSignProvider = 'DocuSign';
    }
}