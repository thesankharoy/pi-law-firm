public class ReferralPDFService {

    @InvocableMethod(label='Send Referral Agreement Email')
    public static void sendReferralAgreement(List<String> intakeIds) {

        String intakeId;
        for (String s : intakeIds) { intakeId = s; }

        try {
            Intake__c intake = [
                SELECT
                    Id, Name, Status__c,
                    Client__c,
                    Client__r.Name, Client__r.Email,
                    Incident_Type__c,
                    Incident_Location__City__s,
                    Incident_Location__StateCode__s
                FROM Intake__c
                WHERE Id = :intakeId
                LIMIT 1
            ];

            if (intake.Client__c == null) {
                throw new AuraHandledException('Intake not linked to a Contact.');
            }

            List<Contact> conList = [
                SELECT Id, Name, Email
                FROM Contact
                WHERE Id = :intake.Client__c
                LIMIT 1
            ];

            if (conList.isEmpty()) {
                throw new AuraHandledException('Contact record not found.');
            }

            Contact con = conList[0];

            if (String.isBlank(con.Email)) {
                throw new AuraHandledException('Contact has no email address.');
            }

            // ── 1. Generate PDF via VF page ─────────────────────────
            PageReference pdfPage = Page.ReferralAgreement;
            pdfPage.getParameters().put('id', intake.Id);

            Blob pdfBlob;
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('test-referral-pdf');
            } else {
                pdfBlob = pdfPage.getContentAsPDF();
            }

            // ── 2. Save PDF as ContentVersion on the Intake ──────────
            ContentVersion cv = new ContentVersion(
                Title                  = intake.Name + '_ReferralAgreement_' + System.now().format('yyyyMMddHHmmss') + '.pdf',
                PathOnClient           = intake.Name + '_ReferralAgreement_' + System.now().format('yyyyMMddHHmmss') + '.pdf',
                VersionData            = pdfBlob,
                FirstPublishLocationId = intake.Id,
                Origin                 = 'C'
            );
            insert cv;

            // ── 3. Build Accept / Reject URLs ────────────────────────
            //    Reuses the same URL pattern as retainer emails.
            //    Custom Label: Referral_Status_Update_URL
            //    (same format as Intake_Status_Update_URL — base URL ending in ?id=)
            String baseUrl    = System.Label.Intake_Status_Update_URL;
            String acceptUrl  = baseUrl + intake.Id + '&varIntakeStatus=Referred%20Out';
            String rejectUrl  = baseUrl + intake.Id + '&varIntakeStatus=Turned%20Down';

            // ── 4. Build location string for email copy ──────────────
            String locationStr = '';
            if (String.isNotBlank(intake.Incident_Location__City__s))
                locationStr += intake.Incident_Location__City__s;
            if (String.isNotBlank(intake.Incident_Location__StateCode__s))
                locationStr += (locationStr != '' ? ', ' : '') + intake.Incident_Location__StateCode__s;

            // ── 5. Build HTML email body ─────────────────────────────
            String emailBody =
                'Dear ' + con.Name + ',<br><br>' +
                'Thank you for reaching out to us regarding your ' +
                (String.isNotBlank(intake.Incident_Type__c) ? intake.Incident_Type__c : 'legal matter') +
                (String.isNotBlank(locationStr) ? ' in ' + locationStr : '') + '.<br><br>' +
                'After careful review, we have determined that we are unable to represent you in this matter at this time. ' +
                'However, we want to ensure you receive the legal help you deserve, so we are proposing to refer your case ' +
                'to qualified legal counsel who may be better positioned to assist you.<br><br>' +
                '<b>Intake Reference:</b> ' + intake.Name + '<br><br>' +
                'Please review the <b>Referral Agreement</b> attached to this email. ' +
                'It explains the terms of the referral, including any potential referral fee arrangement, ' +
                'and confirms your consent to share your case information with the receiving attorney.<br><br>' +
                '<b>Please click one of the buttons below to respond:</b><br><br>' +
                '<table cellpadding="0" cellspacing="0" border="0" style="margin: 20px 0;">' +
                '  <tr>' +
                '    <td style="padding-right:14px;">' +
                '      <a href="' + acceptUrl + '" ' +
                '         style="display:inline-block; padding:12px 28px; background-color:#1a3c5e; color:#ffffff; ' +
                '                text-decoration:none; font-family:Arial,sans-serif; font-size:13px; ' +
                '                font-weight:bold; border-radius:4px;">&#10003;&nbsp; Accept Referral</a>' +
                '    </td>' +
                '    <td>' +
                '      <a href="' + rejectUrl + '" ' +
                '         style="display:inline-block; padding:12px 28px; background-color:#c62828; color:#ffffff; ' +
                '                text-decoration:none; font-family:Arial,sans-serif; font-size:13px; ' +
                '                font-weight:bold; border-radius:4px;">&#10007;&nbsp; Decline Referral</a>' +
                '    </td>' +
                '  </tr>' +
                '</table>' +
                '<p style="font-size:11px; color:#666;">If you have questions before responding, please call our office. ' +
                'Declining does not affect your ability to seek other legal counsel.</p>' +
                'Warm regards,<br><b>The Intake Team</b>';

            // ── 6. Send email ────────────────────────────────────────
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new String[]{ con.Email });
            email.setSubject('Referral Agreement — ' + intake.Name);
            email.setHTMLBody(emailBody);
            email.setTargetObjectId(con.Id);
            email.setWhatId(intake.Id);
            email.setSaveAsActivity(false);

            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName(intake.Name + '_ReferralAgreement.pdf');
            attachment.setBody(pdfBlob);
            attachment.setContentType('application/pdf');
            email.setFileAttachments(new Messaging.EmailFileAttachment[]{ attachment });

            Messaging.SendEmailResult[] results = Messaging.sendEmail(
                new Messaging.SingleEmailMessage[]{ email }
            );

            if (results != null && !results[0].isSuccess()) {
                throw new AuraHandledException(
                    'Email send failed: ' + results[0].getErrors()[0].getMessage()
                );
            }

            System.debug('Referral agreement email sent to: ' + con.Email);

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            System.debug('ReferralPDFService Error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException('Failed to send referral agreement: ' + e.getMessage());
        }
    }
}