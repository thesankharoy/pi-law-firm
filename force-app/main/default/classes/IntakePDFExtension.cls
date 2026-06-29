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
                Id, Name,                                    // {!retainerRefNumber}
                
                // Client — {!clientFullName}, {!clientPhone}, {!clientEmail}
                Client__c,
                Client__r.Name, Client__r.Email, Client__r.Phone,
                // Client Personal — {!clientDOB}
                Date_of_Birth__c,
                // Incident — {!incidentType}, {!incidentDate}, {!incidentLocation}
                Incident_Type__c,
                Incident_Date__c,
                Incident_Location__Street__s, Incident_Location__City__s,
                Incident_Location__StateCode__s, Incident_Location__PostalCode__s,
                Incident_Location__CountryCode__s,
                // Opposing — {!opposingParty}, {!opposingInsurance}
                Opposing_Driver_Name__c,
                Opposing_Carrier__c,
                // Admin — email body (Status, Intake Rep)
                Status__c,
                Intake_Rep__c, Intake_Rep__r.Name
            FROM Intake__c
            WHERE Id = :rec.Id
            LIMIT 1
        ];

        this.intakeId        = this.intake.Id;
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

        // 1. Parties — PDF Section I
        IntakeSectionGroup partiesGrp = new IntakeSectionGroup();
        partiesGrp.sectionName = 'Parties';
        partiesGrp.fields = new List<FieldEntry>();
        partiesGrp.fields.add(fe('Client Name',   intake.Client__r?.Name));
        partiesGrp.fields.add(fe('Date of Birth', formatDate(intake.Date_of_Birth__c)));
        partiesGrp.fields.add(fe('Phone',         intake.Client__r?.Phone));
        partiesGrp.fields.add(fe('Email',         intake.Client__r?.Email));
        this.groupedSections.add(partiesGrp);

        // 2. Matter Description — PDF Section II
        IntakeSectionGroup matterGrp = new IntakeSectionGroup();
        matterGrp.sectionName = 'Matter Description';
        matterGrp.fields = new List<FieldEntry>();
        matterGrp.fields.add(fe('Type of Incident',    intake.Incident_Type__c));
        matterGrp.fields.add(fe('Date of Incident',    formatDate(intake.Incident_Date__c)));
        matterGrp.fields.add(fe('Location',            buildAddress(
            intake.Incident_Location__Street__s,
            intake.Incident_Location__City__s,
            intake.Incident_Location__StateCode__s,
            intake.Incident_Location__PostalCode__s,
            intake.Incident_Location__CountryCode__s)));
        matterGrp.fields.add(fe('Opposing Party',      intake.Opposing_Driver_Name__c));
        matterGrp.fields.add(fe('Insurance Carrier',   intake.Opposing_Carrier__c));
        this.groupedSections.add(matterGrp);

        // 3. Agreement Info — PDF header / footer / email body
        IntakeSectionGroup agreementGrp = new IntakeSectionGroup();
        agreementGrp.sectionName = 'Agreement Info';
        agreementGrp.fields = new List<FieldEntry>();
        agreementGrp.fields.add(fe('Agreement No.', intake.Name));
        //agreementGrp.fields.add(fe('Date',          formatDate(intake.Intake_Date__c?.date())));
        agreementGrp.fields.add(fe('Status',        intake.Status__c));
        agreementGrp.fields.add(fe('Intake Rep',    intake.Intake_Rep__r?.Name));
        this.groupedSections.add(agreementGrp);
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
                fw.id       = cv.Id;
                fw.name     = cv.Title;
                fw.type     = cv.FileType;
                fw.size     = (Decimal.valueOf(cv.ContentSize) / 1024).setScale(2);
                fw.isImage  = imageTypes.contains(cv.FileType.toUpperCase());
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
                Name                             = cv.Title,
                ContentVersionId                 = cv.Id,
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
                SELECT
                    Id, Name, Status__c,
                    Client__c, Client__r.Name, Client__r.Email,
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
            PageReference pdfPage = Page.RetainerAgreement;
            pdfPage.getParameters().put('id', intake.Id);
            Blob pdfBlob;
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('test');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }

            // Save PDF as ContentVersion linked to Intake
            ContentVersion cv = new ContentVersion(
                Title                  = intake.Name + '_RetainerAgreement_' + System.now().format('yyyyMMddHHmmss') + '.pdf',
                PathOnClient           = intake.Name + '_RetainerAgreement_' + System.now().format('yyyyMMddHHmmss') + '.pdf',
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

            String baseUrl    = System.Label.Intake_Status_Update_URL;
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
                '      <a href="' + approveUrl + '" style="display:inline-block; padding:10px 24px; background-color:#2e7d32; color:#ffffff; text-decoration:none; font-family:Arial,sans-serif; font-size:13px; font-weight:bold; border-radius:4px;">Approve</a>' +
                '    </td>' +
                '    <td>' +
                '      <a href="' + rejectUrl + '" style="display:inline-block; padding:10px 24px; background-color:#c62828; color:#ffffff; text-decoration:none; font-family:Arial,sans-serif; font-size:13px; font-weight:bold; border-radius:4px;">Reject</a>' +
                '    </td>' +
                '  </tr>' +
                '</table>' +
                'Warm regards,<br><b>The Intake Team</b>';

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new String[]{ con.Email });
            email.setSubject('Retainer Agreement: ' + intake.Name);
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