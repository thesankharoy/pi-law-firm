public class IntakePDFExtension {
    public List<IntakeSectionGroup> groupedSections { get; set; }
    public List<FileWrapper> intakeFiles { get; set; }
    public Intake__c intake { get; set; }
    public Contact contactRecord { get; set; }
    public Id intakeId;
    public Id intakeContactId;

    // ─── Inner Classes ───────────────────────────────────────────────
    public class IntakeSectionGroup {
        public String sectionName { get; set; }
        public List<FieldEntry> fields { get; set; }
    }

    public class FieldEntry {
        public String label { get; set; }
        public String value { get; set; }
    }

    public class FileWrapper {
        public String id { get; set; }
        public String name { get; set; }
        public String type { get; set; }
        public Decimal size { get; set; }
        public String downloadUrl { get; set; }
        public String viewUrl { get; set; }
        public String thumbnailUrl { get; set; }
        public Boolean isImage { get; set; }
        public Datetime modifiedDate { get; set; }
    }

    // ─── Constructor ─────────────────────────────────────────────────
    public IntakePDFExtension(ApexPages.StandardController stdController) {
        Intake__c rec = (Intake__c) stdController.getRecord();

        this.intake = [
            SELECT
                Id, Name,
                // Incident
                Incident_Date__c, Incident_Time__c, Incident_Type__c,
                Incident_Location__Street__s, Incident_Location__City__s,
                Incident_Location__StateCode__s, Incident_Location__PostalCode__s,
                Incident_Location__CountryCode__s,
                // Client
                Client__c, Client__r.Name, Client__r.Email, Client__r.Phone,
                // Injury
                Was_Injured__c, Injury_Severity__c, Injury_Types__c,
                Body_Parts_Affected__c, Current_Symptoms__c,
                Serious_Injury__c,
                // Medical
                ER_Visit__c, ER_Visit_Date__c, ER_Hospital_Name__c,
                Hospitalized__c, Hospitalization_Start__c, Hospitalization_End__c,
                Medical_Treatment_Status__c, Last_Treatment_Date__c,
                Primary_Provider_Name__c, Primary_Provider_Phone__c, Primary_Provider_Type__c,
                Estimated_Medical_Bills__c,
                // Vehicle / Opposing
                Client_Vehicle_Year__c, Client_Vehicle_Make__c, Client_Vehicle_Model__c,
                Client_Wearing_Seatbelt__c, Client_Airbags_Deployed__c, Client_Vehicle_Damage__c,
                Client_At_Fault__c, Client_Fault_Percent__c,
                Opposing_Driver_Name__c, Opposing_Vehicle_Year__c,
                Opposing_Vehicle_Make__c, Opposing_Vehicle_Model__c,
                Opposing_Carrier__c, Opposing_Liability_Limits__c,
                Opposing_Claim_Number__c, Opposing_Policy_Number__c,
                Opposing_Adjuster_Name__c, Opposing_Adjuster_Phone__c,
                License_Plate_Opposing__c,
                // Insurance
                Client_Ins_Carrier__c, Client_Policy_Number__c,
                Client_Policy_Limits__c, Client_Has_Med_Pay__c,
                Client_Med_Pay_Limits__c, Client_UM_Limits__c,
                // Scene
                Police_Called__c, Police_Report_Filed__c, Police_Report_Number__c,
                Reporting_Agency__c, Citation_Issued__c, Citation_Issued_To__c,
                Witnesses_Present__c, Witness_Count__c,
                Photos_Taken_at_Scene__c, Dashcam_Available__c, Video_Available__c,
                Road_Conditions__c, Weather_Conditions__c,
                DUI_Involved__c, Hit_and_Run__c, Commercial_Vehicle__c,
                Government_Vehicle__c, Other_Vehicles_Involved__c,
                Injury_at_Scene__c, Transported_by_Ambulance__c,
                // Client Personal
                Date_of_Birth__c, Gender__c, Marital_Status__c,
                Has_Minor_Children__c, Preferred_Language__c,
                Employment_Status__c, Employer_Name__c, Employer_Phone__c,
                Hours_Worked_Per_Week__c, Annual_Income__c,
                Has_Health_Insurance__c, Health_Insurance_Carrier__c,
                Pre_Existing_Conditions__c, Pre_Existing_Description__c,
                // Status / Admin
                Status__c, Intake_Method__c, Intake_Date__c,
                Source__c, Intake_Rep__c, Intake_Rep__r.Name,
                Qualified__c, Qualification_Score__c,
                Statute_of_Limitations__c, Statute_of_Limitations_Date__c,
                Liability_Clarity__c, Liability_Notes__c,
                Incident_Description__c, Intake_Notes__c,
                // AI Fields
                AI_Summary__c, AI_Sentiment__c,
                AI_Recommended_Action__c, AI_Next_Recommended_Action__c,
                AI_Conversation_Summary__c
            FROM Intake__c
            WHERE Id = :rec.Id
            LIMIT 1
        ];

        this.intakeId = this.intake.Id;
        this.intakeContactId = this.intake.Client__c;

        if (this.intake.Client__c != null) {
            try {
                this.contactRecord = [
                    SELECT Id, Name, Email, Phone
                    FROM Contact
                    WHERE Id = :this.intake.Client__c
                    LIMIT 1
                ];
            } catch (Exception e) {
                System.debug('Contact not found: ' + e.getMessage());
            }
        }

        buildSections();
        this.intakeFiles = new List<FileWrapper>();
    }

    // ─── Build display sections ───────────────────────────────────────
    private void buildSections() {
        this.groupedSections = new List<IntakeSectionGroup>();

        // 1. Incident Details
        IntakeSectionGroup incidentGrp = new IntakeSectionGroup();
        incidentGrp.sectionName = 'Incident Details';
        incidentGrp.fields = new List<FieldEntry>();
        incidentGrp.fields.add(fe('Incident Date',     formatDate(intake.Incident_Date__c)));
        incidentGrp.fields.add(fe('Incident Time',     formatTime(intake.Incident_Time__c)));
        incidentGrp.fields.add(fe('Incident Type',     intake.Incident_Type__c));
        incidentGrp.fields.add(fe('Incident Location', buildAddress(
            intake.Incident_Location__Street__s,
            intake.Incident_Location__City__s,
            intake.Incident_Location__StateCode__s,
            intake.Incident_Location__PostalCode__s,
            intake.Incident_Location__CountryCode__s)));
        incidentGrp.fields.add(fe('Incident Description', intake.Incident_Description__c));
        this.groupedSections.add(incidentGrp);

        // 2. Client Info
        IntakeSectionGroup clientGrp = new IntakeSectionGroup();
        clientGrp.sectionName = 'Client Information';
        clientGrp.fields = new List<FieldEntry>();
        clientGrp.fields.add(fe('Contact Name',      intake.Client__r?.Name));
        clientGrp.fields.add(fe('Client Name',       intake.Client__r?.Name));
        clientGrp.fields.add(fe('Date of Birth',     formatDate(intake.Date_of_Birth__c)));
        clientGrp.fields.add(fe('Gender',            intake.Gender__c));
        clientGrp.fields.add(fe('Marital Status',    intake.Marital_Status__c));
        clientGrp.fields.add(fe('Has Minor Children',boolVal(intake.Has_Minor_Children__c)));
        clientGrp.fields.add(fe('Preferred Language',intake.Preferred_Language__c));
        clientGrp.fields.add(fe('Employment Status', intake.Employment_Status__c));
        clientGrp.fields.add(fe('Employer Name',     intake.Employer_Name__c));
        clientGrp.fields.add(fe('Employer Phone',    intake.Employer_Phone__c));
        clientGrp.fields.add(fe('Hours/Week',        numVal(intake.Hours_Worked_Per_Week__c)));
        clientGrp.fields.add(fe('Annual Income',     currVal(intake.Annual_Income__c)));
        clientGrp.fields.add(fe('Has Health Insurance', boolVal(intake.Has_Health_Insurance__c)));
        clientGrp.fields.add(fe('Health Insurance Carrier', intake.Health_Insurance_Carrier__c));
        clientGrp.fields.add(fe('Pre-Existing Conditions', boolVal(intake.Pre_Existing_Conditions__c)));
        clientGrp.fields.add(fe('Pre-Existing Description', intake.Pre_Existing_Description__c));
        this.groupedSections.add(clientGrp);

        // 3. Injury Info
        IntakeSectionGroup injuryGrp = new IntakeSectionGroup();
        injuryGrp.sectionName = 'Injury Information';
        injuryGrp.fields = new List<FieldEntry>();
        injuryGrp.fields.add(fe('Was Injured',         boolVal(intake.Was_Injured__c)));
        injuryGrp.fields.add(fe('Injury at Scene',     boolVal(intake.Injury_at_Scene__c)));
        injuryGrp.fields.add(fe('Injury Severity',     intake.Injury_Severity__c));
        injuryGrp.fields.add(fe('Injury Types',        intake.Injury_Types__c));
        injuryGrp.fields.add(fe('Body Parts Affected', intake.Body_Parts_Affected__c));
        injuryGrp.fields.add(fe('Current Symptoms',    intake.Current_Symptoms__c));
        injuryGrp.fields.add(fe('Serious Injury',      boolVal(intake.Serious_Injury__c)));
        injuryGrp.fields.add(fe('Transported by Ambulance', boolVal(intake.Transported_by_Ambulance__c)));
        this.groupedSections.add(injuryGrp);

        // 4. Medical Info
        IntakeSectionGroup medGrp = new IntakeSectionGroup();
        medGrp.sectionName = 'Medical Information';
        medGrp.fields = new List<FieldEntry>();
        medGrp.fields.add(fe('ER Visit',              boolVal(intake.ER_Visit__c)));
        medGrp.fields.add(fe('ER Visit Date',         formatDate(intake.ER_Visit_Date__c)));
        medGrp.fields.add(fe('ER Hospital Name',      intake.ER_Hospital_Name__c));
        medGrp.fields.add(fe('Hospitalized',          boolVal(intake.Hospitalized__c)));
        medGrp.fields.add(fe('Hospitalization Start', formatDate(intake.Hospitalization_Start__c)));
        medGrp.fields.add(fe('Hospitalization End',   formatDate(intake.Hospitalization_End__c)));
        medGrp.fields.add(fe('Treatment Status',      intake.Medical_Treatment_Status__c));
        medGrp.fields.add(fe('Last Treatment Date',   formatDate(intake.Last_Treatment_Date__c)));
        medGrp.fields.add(fe('Primary Provider',      intake.Primary_Provider_Name__c));
        medGrp.fields.add(fe('Provider Phone',        intake.Primary_Provider_Phone__c));
        medGrp.fields.add(fe('Provider Type',         intake.Primary_Provider_Type__c));
        medGrp.fields.add(fe('Est. Medical Bills',    currVal(intake.Estimated_Medical_Bills__c)));
        this.groupedSections.add(medGrp);

        // 5. Vehicle / Opposing Party
        IntakeSectionGroup vehicleGrp = new IntakeSectionGroup();
        vehicleGrp.sectionName = 'Vehicle & Opposing Party';
        vehicleGrp.fields = new List<FieldEntry>();
        vehicleGrp.fields.add(fe('Client Vehicle',       numVal(intake.Client_Vehicle_Year__c) + ' ' + strSafe(intake.Client_Vehicle_Make__c) + ' ' + strSafe(intake.Client_Vehicle_Model__c)));
        vehicleGrp.fields.add(fe('Client Wearing Seatbelt', intake.Client_Wearing_Seatbelt__c));
        vehicleGrp.fields.add(fe('Airbags Deployed',    boolVal(intake.Client_Airbags_Deployed__c)));
        vehicleGrp.fields.add(fe('Client Vehicle Damage', intake.Client_Vehicle_Damage__c));
        vehicleGrp.fields.add(fe('Client At Fault',     intake.Client_At_Fault__c));
        vehicleGrp.fields.add(fe('Client Fault %',      numVal(intake.Client_Fault_Percent__c)));
        vehicleGrp.fields.add(fe('Opposing Driver',     intake.Opposing_Driver_Name__c));
        vehicleGrp.fields.add(fe('Opposing Vehicle',    numVal(intake.Opposing_Vehicle_Year__c) + ' ' + strSafe(intake.Opposing_Vehicle_Make__c) + ' ' + strSafe(intake.Opposing_Vehicle_Model__c)));
        vehicleGrp.fields.add(fe('Opposing License Plate', intake.License_Plate_Opposing__c));
        vehicleGrp.fields.add(fe('Opposing Carrier',    intake.Opposing_Carrier__c));
        vehicleGrp.fields.add(fe('Opposing Liability Limits', currVal(intake.Opposing_Liability_Limits__c)));
        vehicleGrp.fields.add(fe('Opposing Claim #',   intake.Opposing_Claim_Number__c));
        vehicleGrp.fields.add(fe('Opposing Policy #',  intake.Opposing_Policy_Number__c));
        vehicleGrp.fields.add(fe('Opposing Adjuster',  intake.Opposing_Adjuster_Name__c));
        vehicleGrp.fields.add(fe('Adjuster Phone',     intake.Opposing_Adjuster_Phone__c));
        this.groupedSections.add(vehicleGrp);

        // 6. Insurance
        IntakeSectionGroup insGrp = new IntakeSectionGroup();
        insGrp.sectionName = 'Client Insurance';
        insGrp.fields = new List<FieldEntry>();
        insGrp.fields.add(fe('Client Ins. Carrier',  intake.Client_Ins_Carrier__c));
        insGrp.fields.add(fe('Policy Number',        intake.Client_Policy_Number__c));
        insGrp.fields.add(fe('Policy Limits',        currVal(intake.Client_Policy_Limits__c)));
        insGrp.fields.add(fe('Has Med Pay',          boolVal(intake.Client_Has_Med_Pay__c)));
        insGrp.fields.add(fe('Med Pay Limits',       currVal(intake.Client_Med_Pay_Limits__c)));
        insGrp.fields.add(fe('UM Limits',            currVal(intake.Client_UM_Limits__c)));
        this.groupedSections.add(insGrp);

        // 7. Scene Details
        IntakeSectionGroup sceneGrp = new IntakeSectionGroup();
        sceneGrp.sectionName = 'Scene Details';
        sceneGrp.fields = new List<FieldEntry>();
        sceneGrp.fields.add(fe('Police Called',       boolVal(intake.Police_Called__c)));
        sceneGrp.fields.add(fe('Police Report Filed', intake.Police_Report_Filed__c));
        sceneGrp.fields.add(fe('Police Report #',     intake.Police_Report_Number__c));
        sceneGrp.fields.add(fe('Reporting Agency',    intake.Reporting_Agency__c));
        sceneGrp.fields.add(fe('Citation Issued',     boolVal(intake.Citation_Issued__c)));
        sceneGrp.fields.add(fe('Citation Issued To',  intake.Citation_Issued_To__c));
        sceneGrp.fields.add(fe('Witnesses Present',   boolVal(intake.Witnesses_Present__c)));
        sceneGrp.fields.add(fe('Witness Count',       numVal(intake.Witness_Count__c)));
        sceneGrp.fields.add(fe('Photos at Scene',     boolVal(intake.Photos_Taken_at_Scene__c)));
        sceneGrp.fields.add(fe('Dashcam Available',   boolVal(intake.Dashcam_Available__c)));
        sceneGrp.fields.add(fe('Video Available',     boolVal(intake.Video_Available__c)));
        sceneGrp.fields.add(fe('Road Conditions',     intake.Road_Conditions__c));
        sceneGrp.fields.add(fe('Weather Conditions',  intake.Weather_Conditions__c));
        sceneGrp.fields.add(fe('DUI Involved',        boolVal(intake.DUI_Involved__c)));
        sceneGrp.fields.add(fe('Hit and Run',         boolVal(intake.Hit_and_Run__c)));
        sceneGrp.fields.add(fe('Commercial Vehicle',  boolVal(intake.Commercial_Vehicle__c)));
        sceneGrp.fields.add(fe('Government Vehicle',  boolVal(intake.Government_Vehicle__c)));
        sceneGrp.fields.add(fe('Other Vehicles',      numVal(intake.Other_Vehicles_Involved__c)));
        this.groupedSections.add(sceneGrp);

        // 8. Case Status / Admin
        IntakeSectionGroup adminGrp = new IntakeSectionGroup();
        adminGrp.sectionName = 'Case Status & Admin';
        adminGrp.fields = new List<FieldEntry>();
        adminGrp.fields.add(fe('Status',             intake.Status__c));
        adminGrp.fields.add(fe('Intake Method',      intake.Intake_Method__c));
        adminGrp.fields.add(fe('Intake Date',        formatDatetime(intake.Intake_Date__c)));
        adminGrp.fields.add(fe('Source',             intake.Source__c));
        adminGrp.fields.add(fe('Intake Rep',         intake.Intake_Rep__r?.Name));
        adminGrp.fields.add(fe('Qualified',          boolVal(intake.Qualified__c)));
        adminGrp.fields.add(fe('Qualification Score',numVal(intake.Qualification_Score__c)));
        adminGrp.fields.add(fe('Statute of Limitations', formatDate(intake.Statute_of_Limitations_Date__c)));
        adminGrp.fields.add(fe('Liability Clarity',  intake.Liability_Clarity__c));
        adminGrp.fields.add(fe('Liability Notes',    intake.Liability_Notes__c));
        adminGrp.fields.add(fe('Intake Notes',       intake.Intake_Notes__c));
        this.groupedSections.add(adminGrp);

        // 9. AI Summary
        IntakeSectionGroup aiGrp = new IntakeSectionGroup();
        aiGrp.sectionName = 'AI Analysis';
        aiGrp.fields = new List<FieldEntry>();
        aiGrp.fields.add(fe('AI Sentiment',                intake.AI_Sentiment__c));
        aiGrp.fields.add(fe('AI Summary',                  intake.AI_Summary__c));
        aiGrp.fields.add(fe('AI Recommended Action',       intake.AI_Recommended_Action__c));
        aiGrp.fields.add(fe('AI Next Recommended Action',  intake.AI_Next_Recommended_Action__c));
        aiGrp.fields.add(fe('AI Conversation Summary',     intake.AI_Conversation_Summary__c));
        this.groupedSections.add(aiGrp);
    }

    // ─── Init Files ───────────────────────────────────────────────────
    public PageReference initPublicFiles() {
        if (this.intakeId != null) {
            Set<String> imageTypes = new Set<String>{'PNG','JPG','JPEG','GIF','BMP','SVG'};
            Set<Id> contentDocumentIds = new Set<Id>();

            for (ContentDocumentLink link : [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :this.intakeId
            ]) {
                contentDocumentIds.add(link.ContentDocumentId);
            }

            Map<Id, ContentDistribution> existingDistributions = new Map<Id, ContentDistribution>();
            for (ContentDistribution cd : [
                SELECT Id, ContentVersionId, DistributionPublicUrl, ContentDownloadUrl
                FROM ContentDistribution
                WHERE ContentVersionId IN (
                    SELECT Id FROM ContentVersion
                    WHERE ContentDocumentId IN :contentDocumentIds
                    AND IsLatest = true
                )
            ]) {
                existingDistributions.put(cd.ContentVersionId, cd);
            }

            for (ContentVersion cv : [
                SELECT Id, Title, FileType, ContentSize, FileExtension,
                       ContentDocumentId, VersionData, ContentUrl, LastModifiedDate
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocumentIds
                AND IsLatest = true
                ORDER BY Title
            ]) {
                FileWrapper fw = new FileWrapper();
                fw.id   = cv.Id;
                fw.name = cv.Title;
                fw.type = cv.FileType;
                fw.size = (Decimal.valueOf(cv.ContentSize) / 1024).setScale(2);
                fw.isImage = imageTypes.contains(cv.FileType.toUpperCase());
                fw.modifiedDate = cv.LastModifiedDate;

                if (existingDistributions.containsKey(cv.Id)) {
                    ContentDistribution cd = existingDistributions.get(cv.Id);
                    fw.viewUrl     = cd.DistributionPublicUrl;
                    fw.downloadUrl = cd.ContentDownloadUrl;
                } else {
                    ContentDistribution newDist = makeFilePublic(cv);
                    if (newDist != null) {
                        fw.viewUrl     = newDist.DistributionPublicUrl;
                        fw.downloadUrl = newDist.ContentDownloadUrl;
                    }
                }

                if (fw.isImage) {
                    fw.thumbnailUrl = '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB120BY90&versionId=' + cv.Id;
                }

                intakeFiles.add(fw);
            }
        }
        return null;
    }

    public static ContentDistribution makeFilePublic(ContentVersion cv) {
        try {
            ContentDistribution cd = new ContentDistribution(
                Name                            = cv.Title,
                ContentVersionId                = cv.Id,
                PreferencesAllowOriginalDownload = true,
                PreferencesAllowViewInBrowser    = true,
                PreferencesExpires               = false
            );
            insert cd;
            return [
                SELECT DistributionPublicUrl, ContentDownloadUrl
                FROM ContentDistribution
                WHERE Id = :cd.Id
            ];
        } catch (Exception e) {
            System.debug('Error creating public link: ' + e.getMessage());
            return null;
        }
    }

    // ─── InvocableMethod ─────────────────────────────────────────────
    @InvocableMethod(label='Create Intake PDF & Send Email')
public static void saveIntakePdfAndSendEmail(List<String> intakeIds) {
    
    String intakeId;
    for (String s : intakeIds) { intakeId = s; }

    try {
        Intake__c intake = [
            SELECT Id, Name, Status__c, Client__c,
                   Client__r.Name, Client__r.Email,
                   Incident_Type__c,
                   Incident_Location__City__s, Incident_Location__StateCode__s
            FROM Intake__c
            WHERE Id = :intakeId
            LIMIT 1
        ];

        if (intake.Client__c == null) {
            throw new AuraHandledException('Intake not linked to contact!');
        }

        List<Contact> conList = [
            SELECT Id, Name, Email
            FROM Contact
            WHERE Id = :intake.Client__c
            LIMIT 1
        ];

        if (conList.isEmpty()) {
            throw new AuraHandledException('Could not find Contact record!');
        }

        Contact con = conList[0];

        if (String.isBlank(con.Email)) {
            throw new AuraHandledException('Contact Email is blank!');
        }

        // Build PDF
        PageReference pdfPage = Page.IntakePDFPage;
        pdfPage.getParameters().put('id', intake.Id);
        Blob pdfBlob;
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('test');
        } else {
            pdfBlob = pdfPage.getContentAsPDF();
        }

        // Save PDF as ContentVersion linked to Intake
        ContentVersion cv = new ContentVersion(
            Title                  = intake.Name + '_IntakePDF_' + System.now().format('yyyyMMddHHmmss') + '.pdf',
            PathOnClient           = intake.Name + '_' + System.now().format('yyyyMMddHHmmss') + '.pdf',
            VersionData            = pdfBlob,
            FirstPublishLocationId = intake.Id,
            Origin                 = 'C'
        );
        insert cv;

        // Build location string
        String locationStr = '';
        if (String.isNotBlank(intake.Incident_Location__City__s))
            locationStr += intake.Incident_Location__City__s;
        if (String.isNotBlank(intake.Incident_Location__StateCode__s))
            locationStr += (locationStr != '' ? ', ' : '') + intake.Incident_Location__StateCode__s;

        
        String baseUrl = System.Label.Intake_Status_Update_URL;

String approveUrl = baseUrl + intake.Id + '&varIntakeStatus=Retainer%20Agreement%20Signed';
String rejectUrl  = baseUrl + intake.Id + '&varIntakeStatus=Turned%20Down';

        // Email body
        String emailBody =
            'Dear ' + con.Name + ',<br><br>' +
            'Please find attached the intake summary document for your ' +
            (String.isNotBlank(intake.Incident_Type__c) ? intake.Incident_Type__c : 'incident') +
            (String.isNotBlank(locationStr) ? ' case in ' + locationStr : '') + '.<br><br>' +
            'This document contains all the information collected during your intake process. ' +
            'Please review it carefully and contact us if you notice any discrepancies or have additional information to provide.<br><br>' +
            '<b>Intake Reference:</b> ' + intake.Name + '<br>' +
            '<b>Status:</b> ' + (intake.Status__c != null ? intake.Status__c : 'N/A') + '<br><br>' +
            'If you have any questions or need to provide additional details, please do not hesitate to reach out to our team.<br><br>' +
            'We appreciate your cooperation and will be in touch with you shortly.<br><br>' +
            '<table cellpadding="0" cellspacing="0" border="0" style="margin: 24px 0;">' +
            '  <tr>' +
            
            '    <td style="padding-right:12px;">' +
            '      <a href="' + approveUrl + '" style="display:inline-block; padding:10px 24px; background-color:#2e7d32; color:#ffffff; text-decoration:none; font-family:Arial,sans-serif; font-size:13px; font-weight:bold; border-radius:4px;">Approved</a>' +
            '    </td>' +
            '    <td>' +
            '      <a href="' + rejectUrl + '" style="display:inline-block; padding:10px 24px; background-color:#c62828; color:#ffffff; text-decoration:none; font-family:Arial,sans-serif; font-size:13px; font-weight:bold; border-radius:4px;">Rejected</a>' +
            '    </td>' +
            '  </tr>' +
            '</table>' +
            'Warm regards,<br><b>The Intake Team</b>';

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[]{ con.Email });
        email.setSubject('Intake Summary: ' + intake.Name);
        email.setHTMLBody(emailBody);
        email.setTargetObjectId(con.Id);
        email.setWhatId(intake.Id);
        email.setSaveAsActivity(false);

        Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
        attachment.setFileName(intake.Name + '.pdf');
        attachment.setBody(pdfBlob);
        attachment.setContentType('application/pdf');
        email.setFileAttachments(new Messaging.EmailFileAttachment[]{ attachment });

        Messaging.SendEmailResult[] results = Messaging.sendEmail(
            new Messaging.SingleEmailMessage[]{ email }
        );

        if (results != null && results[0].isSuccess()) {
            System.debug('Email sent to: ' + con.Email);
        } else {
            for (Messaging.SendEmailError err : results[0].getErrors()) {
                System.debug('Email Error: ' + err.getMessage() + ' | Status: ' + err.getStatusCode());
            }
            throw new AuraHandledException('Email failed: ' + results[0].getErrors()[0].getMessage());
        }

    } catch (Exception e) {
        System.debug('IntakePDFExtension Error: ' + e.getMessage());
    }
}

    // ─── Helper Methods ───────────────────────────────────────────────
    private FieldEntry fe(String label, String val) {
        FieldEntry f = new FieldEntry();
        f.label = label;
        f.value = String.isNotBlank(val) ? val : '';
        return f;
    }

    private String formatDate(Date d) {
        return d != null ? d.format() : '';
    }

    private String formatDatetime(Datetime dt) {
        return dt != null ? dt.format('MM/dd/yyyy hh:mm a') : '';
    }

    private String formatTime(Time t) {
        if (t == null) return '';
        Integer h = t.hour();
        Integer m = t.minute();
        String ampm = h >= 12 ? 'PM' : 'AM';
        h = Math.mod(h, 12);
        if (h == 0) h = 12;
        return h + ':' + (m < 10 ? '0' : '') + m + ' ' + ampm;
    }

    private String boolVal(Boolean b) {
        if (b == null) return '';
        return b ? 'Yes' : 'No';
    }

    private String currVal(Decimal d) {
        if (d == null) return '';
        return '$' + d.setScale(2).toPlainString();
    }

    private String numVal(Decimal d) {
        if (d == null) return '';
        return String.valueOf(d.longValue());
    }

    private String strSafe(String s) {
        return s != null ? s : '';
    }

    private String buildAddress(String street, String city, String state, String zip, String country) {
        String addr = '';
        if (String.isNotBlank(street))  addr += street + ', ';
        if (String.isNotBlank(city))    addr += city + ', ';
        if (String.isNotBlank(state))   addr += state + ', ';
        if (String.isNotBlank(zip))     addr += zip + ', ';
        if (String.isNotBlank(country)) addr += country;
        if (addr.endsWith(', ')) addr = addr.substring(0, addr.length() - 2);
        return addr;
    }
    
    
}