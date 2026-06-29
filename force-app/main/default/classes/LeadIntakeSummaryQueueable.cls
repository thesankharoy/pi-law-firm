public with sharing class LeadIntakeSummaryQueueable implements Queueable, Database.AllowsCallouts {

    private Id intakeId;

    public LeadIntakeSummaryQueueable(Id intakeId) {
        this.intakeId = intakeId;
    }

    public void execute(QueueableContext qc) {

        System.debug('========== LeadIntakeSummaryQueueable Started ==========');

        try {

            Intake__c intake = [
                SELECT Id,
                       Incident_Type__c,
                       Injury_Severity__c,
                       Medical_Treatment_Status__c,
                       Police_Report_Filed__c,
                       Incident_Age__c,
                       Insurance_Available__c,
                       Liability_Clarity__c,
                       Qualification_Score__c,
                       Case_Quality__c,
                       AI_Summary__c
                FROM Intake__c
                WHERE Id = :intakeId
                LIMIT 1
            ];

            String prompt = buildPrompt(intake);

            HttpRequest req = new HttpRequest();

            req.setEndpoint('callout:Anthropic_Claude/v1/messages');
            req.setMethod('POST');
            req.setTimeout(120000);

            req.setHeader('Content-Type', 'application/json');
            req.setHeader('anthropic-version', '2023-06-01');

            Map<String,Object> body = new Map<String,Object>();

            body.put('model','claude-haiku-4-5-20251001');
            body.put('max_tokens',1200);
            body.put('temperature',0);

            body.put(
                'messages',
                new List<Object>{
                    new Map<String,Object>{
                        'role' => 'user',
                        'content' => prompt
                    }
                }
            );

            req.setBody(JSON.serialize(body));

            System.debug('Calling Claude...');

            Http http = new Http();

            HttpResponse res = http.send(req);

            System.debug('Status Code: ' + res.getStatusCode());
            System.debug('Response: ' + res.getBody());

            if(res.getStatusCode() >= 200 &&
               res.getStatusCode() < 300){

                Map<String,Object> responseMap =
                    (Map<String,Object>)JSON.deserializeUntyped(res.getBody());

                List<Object> content =
                    (List<Object>)responseMap.get('content');

                if(content != null && !content.isEmpty()){

                    Map<String,Object> first =
                        (Map<String,Object>)content[0];

                    intake.AI_Summary__c =
                        (String)first.get('text');

                    update intake;

                    System.debug('Summary Updated Successfully.');

                }else{

                    System.debug('Claude returned empty content.');

                }

            }else{

                System.debug('Claude Error: ' + res.getBody());

            }

        }
        catch(Exception ex){

            System.debug('Exception Type: ' + ex.getTypeName());
            System.debug('Message: ' + ex.getMessage());
            System.debug('Line: ' + ex.getLineNumber());
            System.debug(ex.getStackTraceString());

        }

        System.debug('========== LeadIntakeSummaryQueueable Finished ==========');

    }

    private static String buildPrompt(Intake__c intake){

        return

'You are an AI intake specialist for a personal injury law firm.\n\n' +

'Your role is to generate a short, professional intake summary for human intake staff.\n\n' +

'Analyze the lead details and create a concise case summary highlighting:\n' +
'- Overall case quality\n' +
'- Injury seriousness\n' +
'- Urgency level\n' +
'- Liability strength\n' +
'- Conversion potential\n' +
'- Immediate concerns affecting the case\n\n' +

'Lead Details:\n\n' +

'Accident Type:\n' +
nullToBlank(intake.Incident_Type__c) + '\n\n' +

'Injury Severity:\n' +
nullToBlank(intake.Injury_Severity__c) + '\n\n' +

'Medical Treatment Started:\n' +
nullToBlank(intake.Medical_Treatment_Status__c) + '\n\n' +

'Police Report Available:\n' +
nullToBlank(intake.Police_Report_Filed__c) + '\n\n' +

'Accident Age:\n' +
String.valueOf(intake.Incident_Age__c) + '\n\n' +

'Insurance Available:\n' +
nullToBlank(intake.Insurance_Available__c) + '\n\n' +

'Liability Clarity:\n' +
nullToBlank(intake.Liability_Clarity__c) + '\n\n' +

'Lead Score:\n' +
String.valueOf(intake.Qualification_Score__c) + '\n\n' +

'Lead Temperature:\n' +
nullToBlank(intake.Case_Quality__c) + '\n\n' +

'IMPORTANT RESPONSE RULES:\n' +
'- Generate ONLY the summary\n' +
'- Keep response between 60–120 words\n' +
'- Use 3–5 concise bullet points\n' +
'- Do NOT use headings\n' +
'- Do NOT repeat field labels\n' +
'- Do NOT provide legal advice\n' +
'- Keep language professional and operational\n' +
'- Focus on what intake staff should immediately understand about the lead\n' +
'- Make the summary easy to scan during live intake review\n\n' +

'Example Style:\n' +
'- Strong potential case with clear liability and recent accident timeline.\n' +
'- Injury severity and active medical treatment increase claim value potential.\n' +
'- Warm lead showing strong consultation intent with low delay risk.\n' +
'- Missing police report may require additional documentation support.';

    }

    private static String nullToBlank(String value){

        return String.isBlank(value)
            ? 'Not Provided'
            : value;

    }

}