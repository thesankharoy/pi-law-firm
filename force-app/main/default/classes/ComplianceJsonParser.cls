public with sharing class ComplianceJsonParser {

    public class Request {
        @InvocableVariable(required=true)
        public String jsonResponse;
    }

    public class Response {
        @InvocableVariable
        public Boolean risk;

        @InvocableVariable
        public Integer riskScore;

        @InvocableVariable
        public String riskLevel;

        @InvocableVariable
        public String issueTypes;

        @InvocableVariable
        public String flaggedQuote;

        @InvocableVariable
        public String reason;
    }

    @InvocableMethod(label='Parse Compliance JSON')
    public static List<Response> parse(List<Request> requests) {

        List<Response> results = new List<Response>();

        for(Request req : requests) {

            Map<String,Object> data =
                (Map<String,Object>)JSON.deserializeUntyped(req.jsonResponse);

            Response r = new Response();

            r.risk = (Boolean)data.get('risk');
            r.riskScore = Integer.valueOf(String.valueOf(data.get('riskScore')));
            r.riskLevel = String.valueOf(data.get('riskLevel'));
            r.flaggedQuote = String.valueOf(data.get('flaggedQuote'));
            r.reason = String.valueOf(data.get('reason'));

            Object types = data.get('issueTypes');
            if(types != null){
                r.issueTypes = String.join(
                    (List<String>)JSON.deserialize(
                        JSON.serialize(types),
                        List<String>.class
                    ),
                    ';'
                );
            }

            results.add(r);
        }

        return results;
    }
}