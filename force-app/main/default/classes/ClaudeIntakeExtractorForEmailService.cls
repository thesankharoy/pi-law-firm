public with sharing class ClaudeIntakeExtractorForEmailService {

    public class Request {
        @InvocableVariable(required=true)
        public String emailAddress;

        @InvocableVariable(required=true)
        public String emailSummary;
    }

    public class Response {
        @InvocableVariable
        public String jsonResponse;
    }

    @InvocableMethod(label='Extract Intake from Email using Claude')
    public static List<Response> extract(List<Request> requests) {

        List<Response> responses = new List<Response>();

        for(Request req : requests){

            Response res = new Response();

            try{

                System.debug('Email Address: ' + req.emailAddress);
                System.debug('Email Summary: ' + req.emailSummary);

                String prompt = buildPrompt(
                    req.emailAddress,
                    req.emailSummary
                );

                HttpRequest httpReq = new HttpRequest();

                httpReq.setEndpoint('callout:Anthropic_Claude/v1/messages');
                httpReq.setMethod('POST');

                httpReq.setHeader('Content-Type','application/json');
                httpReq.setHeader('anthropic-version','2023-06-01');

                Map<String,Object> body = new Map<String,Object>();

                body.put('model','claude-haiku-4-5-20251001');
                body.put('max_tokens',1500);

                body.put(
                    'messages',
                    new List<Object>{
                        new Map<String,Object>{
                            'role' => 'user',
                            'content' => prompt
                        }
                    }
                );

                httpReq.setBody(JSON.serialize(body));

                Http http = new Http();

                HttpResponse httpRes = http.send(httpReq);

                if(httpRes.getStatusCode() >= 200 &&
                   httpRes.getStatusCode() < 300){

                    Map<String,Object> responseMap =
                        (Map<String,Object>)JSON.deserializeUntyped(httpRes.getBody());

                    List<Object> content =
                        (List<Object>)responseMap.get('content');

                    Map<String,Object> first =
                        (Map<String,Object>)content[0];

                    res.jsonResponse = (String)first.get('text');

                }else{

                    throw new CalloutException(httpRes.getBody());

                }

            }catch(Exception ex){

                res.jsonResponse =
                    '{"error":"' +
                    ex.getMessage().replace('"','') +
                    '"}';

            }

            responses.add(res);

        }

        return responses;

    }

    private static String buildPrompt(String emailAddress, String emailSummary){

        String prompt =

'You are a Personal Injury Intake Assistant.\n' +
'Analyze the Email Address and Email Summary and extract information into valid JSON.\n' +
'Return ONLY JSON. Do not return explanations, markdown, or additional text.\n' +

'Schema:\n' +
'{\n' +
'"firstName": "",\n' +
'"lastName": "",\n' +
'"email": "",\n' +
'"phone": "",\n' +
'"incidentDate": "",\n' +
'"accidentAge": "",\n' +
'"accidentType": "",\n' +
'"injurySeverity": "",\n' +
'"insuranceAvailable": "",\n' +
'"liabilityClarity": "",\n' +
'"medicalTreatmentStarted": "",\n' +
'"policeReportAvailable": "",\n' +
'"description": "",\n' +
'"summary": "",\n' +
'"missingFields": []\n' +
'}\n' +

'Allowed Values:\n\n' +

'accidentAge:\n' +
'Within 7 Days\n' +
'8–30 Days\n' +
'31–90 Days\n' +
'90+ Days\n\n' +

'accidentType:\n' +
'Truck Accident\n' +
'Car Accident\n' +
'Slip & Fall\n' +
'Motorcycle Accident\n' +
'Dog Bite\n' +
'Medical Malpractice\n\n' +

'injurySeverity:\n' +
'Severe\n' +
'Moderate\n' +
'Minor\n' +
'Critical\n' +
'Fatality\n\n' +

'insuranceAvailable:\n' +
'Commercial\n' +
'Personal\n' +
'Unknown\n' +
'None\n\n' +

'liabilityClarity:\n' +
'Other_Party_Fault\n' +
'Shared_Fault\n' +
'Unclear\n\n' +

'medicalTreatmentStarted:\n' +
'Not Started\n' +
'Active\n' +
'On Hold\n' +
'Discharged\n\n' +

'policeReportAvailable:\n' +
'Yes\n' +
'No\n\n' +

'Instructions:\n' +
'Read the Email Address and Email Summary carefully.\n' +
'Use the Email Address to populate the email field if it is not explicitly mentioned in the summary.\n' +
'Extract all available information.\n' +
'Provide the picklist value exactly as defined.\n' +
'If a value is not found, use an empty string.\n' +
'Add missing information to the missingFields array.\n' +
'Create a concise summary of the case.\n' +
'Return only valid JSON.\n\n' +

'Email Address:\n' +
emailAddress +
'\n\n' +

'Email Summary:\n' +
emailSummary;

        return prompt;

    }

}