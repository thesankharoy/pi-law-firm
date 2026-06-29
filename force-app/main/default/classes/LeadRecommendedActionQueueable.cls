public with sharing class LeadRecommendedActionQueueable implements Queueable, Database.AllowsCallouts {

    private Id intakeId;

    public LeadRecommendedActionQueueable(Id intakeId) {
        this.intakeId = intakeId;
    }

    public void execute(QueueableContext qc) {

        System.debug('========== LeadRecommendedActionQueueable Started ==========');

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
                       AI_Recommended_Action__c
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
            body.put('max_tokens',1800);
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

                    intake.AI_Recommended_Action__c =
                        (String)first.get('text');

                    update intake;

                    System.debug('Recommendation Updated Successfully.');

                } else {

                    System.debug('Claude returned empty content.');

                }

            } else {

                System.debug('Claude Error: ' + res.getBody());

            }

        }
        catch(Exception ex){

            System.debug('Exception Type: ' + ex.getTypeName());
            System.debug('Message: ' + ex.getMessage());
            System.debug('Line: ' + ex.getLineNumber());
            System.debug(ex.getStackTraceString());

        }

        System.debug('========== LeadRecommendedActionQueueable Finished ==========');

    }

    private static String buildPrompt(Intake__c intake){

        return

'You are an elite intake conversion strategist for a personal injury law firm.\n\n' +

'Your job is to help human intake specialists maximize consultation booking probability and reduce lead drop-off.\n\n' +

'Analyze the lead details and provide concise, actionable intake recommendations that help the intake specialist:\n' +
'- Build trust quickly\n' +
'- Increase urgency\n' +
'- Reduce hesitation\n' +
'- Prevent competitor loss\n' +
'- Secure consultation booking\n\n' +

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
'- Keep response short and easy to scan\n' +
'- Maximum 200-300 words\n' +
'- Use bullet points only\n' +
'- Do NOT write paragraphs\n' +
'- Do NOT explain legal concepts\n' +
'- Do NOT repeat lead information\n' +
'- Focus only on practical intake guidance\n' +
'- Make recommendations highly actionable\n' +
'- Write like guidance for a busy intake specialist during a live call\n\n' +

'Use the EXACT format below:\n\n' +

'## Conversion Probability\n' +
'- Likelihood:\n' +
'- Key Opportunity:\n' +
'- Main Risk:\n\n' +

'## Emotional Indicators\n' +
'- Primary Emotion:\n' +
'- Urgency Level:\n' +
'- What Client Needs Most:\n\n' +

'## Competitor Risk\n' +
'- Risk Level:\n' +
'- Why:\n' +
'- Prevention Strategy:\n\n' +

'## Intake Strategy\n' +
'- Best Tone:\n' +
'- Main Persuasion Angle:\n' +
'- Key Trust Builder:\n' +
'- Recommended CTA:\n\n' +

'## Communication Approach\n' +
'- Primary Channel:\n' +
'- Backup Channel:\n' +
'- Avoid:\n\n' +

'## Follow-Up Timing\n' +
'- First Contact:\n' +
'- Second Attempt:\n' +
'- Escalation Timing:\n\n' +

'## Key Talking Points\n' +
'-\n' +
'-\n' +
'-\n\n' +

'## Recommended Immediate Action\n' +
'-\n\n' +

'Return ONLY the formatted response.';

    }

    private static String nullToBlank(String value){

        return String.isBlank(value)
            ? 'Not Provided'
            : value;

    }

}