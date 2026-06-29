public with sharing class CallTranscriptAnalyzer {

    public class Request {
        @InvocableVariable(required=true)
        public String transcript;
    }

    public class Response {
        @InvocableVariable
        public String analysis;
    }

    @InvocableMethod(label='Analyze Call Transcript using Claude')
    public static List<Response> analyze(List<Request> requests) {

        System.debug('================ ClaudeTranscriptAnalyzer Started ================');
        System.debug('Number of Requests: ' + requests.size());

        List<Response> responses = new List<Response>();

        Integer requestNumber = 1;

        for (Request req : requests) {

            System.debug('-----------------------------------------------------------');
            System.debug('Processing Request #' + requestNumber);

            Response res = new Response();

            try {

                System.debug('Transcript Length: ' +
                    (req.transcript == null ? 0 : req.transcript.length()));

                System.debug('Transcript:');
                System.debug(req.transcript);

                System.debug('Building Prompt...');

                String prompt = buildPrompt(req.transcript);

                System.debug('Prompt Length: ' + prompt.length());

                HttpRequest httpReq = new HttpRequest();

                httpReq.setEndpoint('callout:Anthropic_Claude/v1/messages');
                httpReq.setMethod('POST');
                httpReq.setHeader('Content-Type','application/json');
                httpReq.setHeader('anthropic-version','2023-06-01');

                Map<String,Object> body = new Map<String,Object>();

                body.put('model','claude-haiku-4-5-20251001');
                body.put('max_tokens',1200);

                body.put(
                    'messages',
                    new List<Object>{
                        new Map<String,Object>{
                            'role' => 'user',
                            'content' => prompt
                        }
                    }
                );

                String requestBody = JSON.serialize(body);

                httpReq.setBody(requestBody);

                System.debug('Endpoint: ' + httpReq.getEndpoint());
                System.debug('Method: ' + httpReq.getMethod());

                System.debug('================ REQUEST BODY ================');
                System.debug(requestBody);

                System.debug('================ BEFORE HTTP CALLOUT ================');

                Http http = new Http();

                HttpResponse httpRes = http.send(httpReq);

                System.debug('================ AFTER HTTP CALLOUT ================');

                System.debug('Status Code: ' + httpRes.getStatusCode());
                System.debug('Status: ' + httpRes.getStatus());

                System.debug('================ RAW RESPONSE ================');
                System.debug(httpRes.getBody());

                if(httpRes.getStatusCode() >= 200 &&
                   httpRes.getStatusCode() < 300){

                    Map<String,Object> responseMap =
                        (Map<String,Object>)JSON.deserializeUntyped(httpRes.getBody());

                    System.debug('Response Map: ' + responseMap);

                    List<Object> content =
                        (List<Object>)responseMap.get('content');

                    System.debug('Content: ' + content);

                    Map<String,Object> first =
                        (Map<String,Object>)content[0];

                    System.debug('First Content Object: ' + first);

                    res.analysis = (String)first.get('text');

                    System.debug('================ CLAUDE OUTPUT ================');
                    System.debug(res.analysis);

                } else {

                    System.debug('Callout Failed');
                    System.debug('Status Code: ' + httpRes.getStatusCode());
                    System.debug('Response Body: ' + httpRes.getBody());

                    throw new CalloutException(httpRes.getBody());

                }

            } catch(Exception ex){

                System.debug('================ EXCEPTION OCCURRED ================');
                System.debug('Exception Type: ' + ex.getTypeName());
                System.debug('Exception Message: ' + ex.getMessage());
                System.debug('Line Number: ' + ex.getLineNumber());
                System.debug('Stack Trace:');
                System.debug(ex.getStackTraceString());

                res.analysis = 'Error: ' + ex.getMessage();
            }

            responses.add(res);

            System.debug('Final Response: ' + res.analysis);

            requestNumber++;
        }

        System.debug('================ ClaudeTranscriptAnalyzer Finished ================');

        return responses;
    }

    private static String buildPrompt(String transcript){

        String prompt =

'You are an AI assistant helping a sales intake team analyze call transcripts.\n\n' +

'Analyze the transcript below and respond using EXACTLY these section headers with no extra text before or after each section:\n\n' +

'FOLLOW_UP_NOTES:\n' +
'[Write 2-3 sentences summarizing the call - callers purpose, key information gathered, and overall outcome]\n\n' +

'OBJECTIONS_RAISED:\n' +
'[List each objection or concern raised by the caller as bullet points starting with "-". If none, write "None identified."]\n\n' +

'NEXT_STEPS:\n' +
'[List specific, actionable follow-up steps and recommended responses to each objection raised]\n\n' +

'Transcript:\n' +
transcript;

        return prompt;

    }

}