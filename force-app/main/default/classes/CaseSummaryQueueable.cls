public without sharing class CaseSummaryQueueable implements Queueable, Database.AllowsCallouts {

    private final Id intakeId;

    public CaseSummaryQueueable(Id intakeId) {
        this.intakeId = intakeId;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Entry point
    // ─────────────────────────────────────────────────────────────────────────

    public void execute(QueueableContext ctx) {
        try {
            FactSheet fs = buildFactSheet(intakeId);
            String summary = callClaude(fs);
            persistSummary(intakeId, summary);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'CaseSummaryQueueable failed for Intake ' + intakeId + ': ' + e.getMessage()
                + '\n' + e.getStackTraceString());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Step 1: Assemble fact sheet — all computation happens here
    // ─────────────────────────────────────────────────────────────────────────

    @TestVisible
    static FactSheet buildFactSheet(Id intakeId) {

        // Incident_Location__c sub-fields available in this org:
        //   Incident_Location__Street__s
        //   Incident_Location__City__s
        //   Incident_Location__PostalCode__s
        // NOT present: __State__s, __Country__s, __CountryCode__s
        Intake__c intake = [
            SELECT Id, Name, Status__c,
                   Incident_Type__c, Injury_Severity__c, Medical_Treatment_Status__c,
                   Incident_Date__c, CreatedDate, LastModifiedDate,
                   Incident_Description__c,
                   Police_Called__c, Insurance_Available__c, Liability_Clarity__c,
                   Source__c, Sign_Up_Method__c, Qualified__c,
                   Incident_Location__Street__s,
                   Incident_Location__City__s,
                   Incident_Location__PostalCode__s,
                   Client__r.FirstName, Client__r.LastName,
                   Client__r.Email, Client__r.Phone, Client__r.MobilePhone,
                   Client__r.Birthdate,
                   Client__r.MailingStreet, Client__r.MailingCity,
                   Client__r.MailingState, Client__r.MailingPostalCode,
                   Client__r.MailingCountry
            FROM   Intake__c
            WHERE  Id = :intakeId
            LIMIT  1
        ];

        List<Role__c> roles = [
            SELECT Party__r.FirstName, Party__r.LastName,
                   Party__r.Email, Party__r.Phone,
                   Role__c, Primary__c, Comments__c
            FROM   Role__c
            WHERE  Intake__c = :intakeId
            ORDER BY Role__c, Primary__c DESC
        ];

        List<Task> tasks = [
            SELECT Subject, Status, ActivityDate, Description,
                   CreatedDate, Owner.Name
            FROM   Task
            WHERE  WhatId = :intakeId
            ORDER BY ActivityDate ASC NULLS LAST
            LIMIT  50
        ];

        // Document__c: 'Generated' is the status GenerateIntakeAuthDocsQueueable
        // actually writes for HIPAA/LOR docs in this org. 'Active' is not
        // produced by that flow — filtering on 'Active' alone hid every auth
        // document from the fact sheet even when generation succeeded.
        // Document_Type__c is also queried (it does exist in this org,
        // confirmed via GenerateIntakeAuthDocsQueueable) so the summary can
        // name which document is on file (e.g. "HIPAA Authorization") rather
        // than just a generic file name.
        List<Document__c> docs = [
            SELECT Name, Document_Type__c, MIME_Type__c, CreatedDate, Status__c
            FROM   Document__c
            WHERE  Intake__c = :intakeId
              AND  Status__c IN ('Active', 'Generated')
            ORDER BY CreatedDate ASC
        ];

        Date solDeadline = computeSOLDeadline(intake.Incident_Date__c, intake.Incident_Type__c);

        Integer daysFromIncident = intake.Incident_Date__c != null
            ? intake.Incident_Date__c.daysBetween(Date.today()) : null;

        Integer daysLeadToSign = intake.CreatedDate != null
            ? Integer.valueOf(intake.CreatedDate.date().daysBetween(Date.today())) : null;

        FactSheet fs        = new FactSheet();
        fs.intake           = intake;
        fs.roles            = roles;
        fs.tasks            = tasks;
        fs.documents        = docs;
        fs.solDeadline      = solDeadline;
        fs.daysFromIncident = daysFromIncident;
        fs.daysLeadToSign   = daysLeadToSign;
        fs.generatedAt      = System.now();
        return fs;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Statute-of-limitations matrix (2-year default for US PI)
    // ─────────────────────────────────────────────────────────────────────────

    @TestVisible
    static Date computeSOLDeadline(Date incidentDate, String incidentType) {
        if (incidentDate == null) return null;

        Map<String, Integer> solYears = new Map<String, Integer>{
            'Auto Accident'        => 2,
            'Slip and Fall'        => 2,
            'Medical Malpractice'  => 2,
            'Workers Compensation' => 2,
            'Product Liability'    => 2,
            'Dog Bite'             => 2,
            'Wrongful Death'       => 2,
            'Other'                => 2
        };

        Integer years = solYears.containsKey(incidentType)
            ? solYears.get(incidentType) : 2;

        return incidentDate.addYears(years);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Step 2: Call Claude — narrative only, facts pre-supplied
    // ─────────────────────────────────────────────────────────────────────────

    @TestVisible
    static String callClaude(FactSheet fs) {

        String factJson = buildFactJson(fs);

        String systemPrompt =
            'You are a paralegal writing assistant for a personal injury law firm. '
          + 'You receive a structured fact sheet assembled by the firm\'s case management system. '
          + 'Your job is to write a clear, professional case hand-off summary for the attorney. '
          + '\n\nRULES:\n'
          + '1. NEVER invent, estimate, or calculate any fact, date, number, or dollar amount. '
          + '   Use only the values provided in the fact sheet verbatim.\n'
          + '2. If a field is null or missing, write "Not provided" — do not guess.\n'
          + '3. Keep language professional, plain English, no legal jargon beyond standard PI terms.\n'
          + '4. Output plain text only — no Markdown, no bullet symbols, no HTML.\n'
          + '5. Follow the exact section order and headings specified in the user prompt.';

        String userPrompt =
            'Write a case hand-off summary for the attorney using ONLY the fact sheet below. '
          + 'Use these exact section headings (each on its own line, followed by a colon, then the content):\n\n'
          + 'CLIENT\n'
          + 'INCIDENT\n'
          + 'INJURIES AND TREATMENT\n'
          + 'LIABILITY PICTURE\n'
          + 'PARTIES AND INSURANCE\n'
          + 'DOCUMENTS ON FILE\n'
          + 'CONTACT HISTORY\n'
          + 'IMPORTANT DATES\n'
          + 'HAND-OFF NOTES\n\n'
          + '--- FACT SHEET ---\n'
          + factJson;

        Map<String, Object> requestBody = new Map<String, Object>{
            'model'      => 'claude-haiku-4-5',
            'max_tokens' => 1500,
            'system'     => systemPrompt,
            'messages'   => new List<Object>{
                new Map<String, Object>{
                    'role'    => 'user',
                    'content' => userPrompt
                }
            }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Anthropic_Claude/v1/messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('anthropic-version', '2023-06-01');
        req.setTimeout(30000);
        req.setBody(JSON.serialize(requestBody));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CaseSummaryException(
                'Anthropic API error ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> content = (List<Object>) parsed.get('content');
        Map<String, Object> firstBlock = (Map<String, Object>) content[0];
        return (String) firstBlock.get('text');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Build the deterministic JSON fact sheet sent to Claude
    // ─────────────────────────────────────────────────────────────────────────

    @TestVisible
    static String buildFactJson(FactSheet fs) {

        Intake__c i = fs.intake;

        Map<String, Object> client = new Map<String, Object>{
            'name'    => safeStr(i.Client__r.FirstName) + ' ' + safeStr(i.Client__r.LastName),
            'email'   => safeStr(i.Client__r.Email),
            'phone'   => safeStr(i.Client__r.Phone),
            'mobile'  => safeStr(i.Client__r.MobilePhone),
            'dob'     => i.Client__r.Birthdate != null ? String.valueOf(i.Client__r.Birthdate) : null,
            'address' => buildAddress(
                i.Client__r.MailingStreet,     i.Client__r.MailingCity,
                i.Client__r.MailingState,      i.Client__r.MailingPostalCode,
                i.Client__r.MailingCountry
            )
        };

        // Incident location: only Street, City, PostalCode exist in this org
        Map<String, Object> incident = new Map<String, Object>{
            'type'         => safeStr(i.Incident_Type__c),
            'date'         => i.Incident_Date__c != null ? String.valueOf(i.Incident_Date__c) : null,
            'days_since'   => fs.daysFromIncident,
            'location'     => buildAddress(
                i.Incident_Location__Street__s,
                i.Incident_Location__City__s,
                null,
                i.Incident_Location__PostalCode__s,
                null
            ),
            'police_called'  => i.Police_Called__c,
            'description'    => safeStr(i.Incident_Description__c)
        };

        Map<String, Object> medical = new Map<String, Object>{
            'injury_severity'  => safeStr(i.Injury_Severity__c),
            'treatment_status' => safeStr(i.Medical_Treatment_Status__c)
        };

        Map<String, Object> liability = new Map<String, Object>{
            'insurance_available' => safeStr(i.Insurance_Available__c),
            'liability_clarity'   => safeStr(i.Liability_Clarity__c)
        };

        List<Map<String, Object>> roleList = new List<Map<String, Object>>();
        for (Role__c r : fs.roles) {
            roleList.add(new Map<String, Object>{
                'role'     => safeStr(r.Role__c),
                'primary'  => r.Primary__c,
                'name'     => safeStr(r.Party__r.FirstName) + ' ' + safeStr(r.Party__r.LastName),
                'email'    => safeStr(r.Party__r.Email),
                'phone'    => safeStr(r.Party__r.Phone),
                'comments' => safeStr(r.Comments__c)
            });
        }

        // Documents: include Document_Type__c so the summary can name
        // which document is on file (e.g. "HIPAA Authorization") instead
        // of just a generic file name / MIME type.
        List<Map<String, Object>> docList = new List<Map<String, Object>>();
        for (Document__c d : fs.documents) {
            docList.add(new Map<String, Object>{
                'name'     => safeStr(d.Name),
                'doc_type' => safeStr(d.Document_Type__c),
                'mime'     => safeStr(d.MIME_Type__c),
                'uploaded' => String.valueOf(d.CreatedDate.date())
            });
        }

        List<Map<String, Object>> taskList = new List<Map<String, Object>>();
        for (Task t : fs.tasks) {
            taskList.add(new Map<String, Object>{
                'subject' => safeStr(t.Subject),
                'status'  => safeStr(t.Status),
                'date'    => t.ActivityDate != null ? String.valueOf(t.ActivityDate) : null,
                'by'      => safeStr(t.Owner.Name),
                'notes'   => safeStr(t.Description)
            });
        }

        Map<String, Object> dates = new Map<String, Object>{
            'incident_date'      => i.Incident_Date__c != null ? String.valueOf(i.Incident_Date__c) : null,
            'intake_created'     => String.valueOf(i.CreatedDate.date()),
            'retainer_signed'    => String.valueOf(Date.today()),
            'days_lead_to_sign'  => fs.daysLeadToSign,
            'sol_deadline'       => fs.solDeadline != null ? String.valueOf(fs.solDeadline) : null,
            'sol_days_remaining' => fs.solDeadline != null
                                    ? Date.today().daysBetween(fs.solDeadline) : null
        };

        Map<String, Object> factSheet = new Map<String, Object>{
            'intake_id'      => i.Name,
            'generated_at'   => String.valueOf(fs.generatedAt),
            'source'         => safeStr(i.Source__c),
            'sign_up_method' => safeStr(i.Sign_Up_Method__c),
            'client'         => client,
            'incident'       => incident,
            'medical'        => medical,
            'liability'      => liability,
            'roles'          => roleList,
            'documents'      => docList,
            'task_history'   => taskList,
            'important_dates'=> dates
        };

        return JSON.serializePretty(factSheet);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Step 3: Persist
    // ─────────────────────────────────────────────────────────────────────────

    static void persistSummary(Id intakeId, String summary) {
        update new Intake__c(
            Id                      = intakeId,
            Case_Summary__c         = summary,
            Summary_Generated_At__c = System.now(),
            Summary_Reviewed__c     = false
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    static String safeStr(String s) {
        return (s != null && s.trim() != '') ? s.trim() : null;
    }

    static String buildAddress(String street, String city, String state,
                               String postal, String country) {
        List<String> parts = new List<String>();
        if (street  != null && street.trim()  != '') parts.add(street.trim());
        if (city    != null && city.trim()    != '') parts.add(city.trim());
        if (state   != null && state.trim()   != '') parts.add(state.trim());
        if (postal  != null && postal.trim()  != '') parts.add(postal.trim());
        if (country != null && country.trim() != '') parts.add(country.trim());
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Inner types
    // ─────────────────────────────────────────────────────────────────────────

    @TestVisible
    class FactSheet {
        Intake__c         intake;
        List<Role__c>     roles;
        List<Task>        tasks;
        List<Document__c> documents;
        Date              solDeadline;
        Integer           daysFromIncident;
        Integer           daysLeadToSign;
        DateTime          generatedAt;
    }

    public class CaseSummaryException extends Exception {}
}