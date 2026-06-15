public with sharing class IntakeJsonParser {

    public class Request {

        @InvocableVariable(
            required=true
        )
        public String jsonResponse;
    }

    public class Response {

        @InvocableVariable
        public String summary;

        @InvocableVariable
        public String sentiment;

        @InvocableVariable
        public String recommendedAction;

        @InvocableVariable
        public String nextMessage;
    }

    @InvocableMethod(
        label='Parse AI JSON'
    )
    public static List<Response> parse(
        List<Request> requests
    ) {

        List<Response> results =
            new List<Response>();

        for(Request req : requests){

            Map<String,Object> data =

                (Map<String,Object>)

                JSON.deserializeUntyped(
                    req.jsonResponse
                );

            Response r =
                new Response();

            r.summary =
                (String)data.get(
                    'summary'
                );

            r.sentiment =
                (String)data.get(
                    'sentiment'
                );

            r.recommendedAction =
                (String)data.get(
                    'recommendedAction'
                );

            r.nextMessage =
                (String)data.get(
                    'nextMessage'
                );

            results.add(r);
        }

        return results;
    }
}