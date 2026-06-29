public with sharing class LeadIntakeRecommendedActions {

    public class Request {

        @InvocableVariable(required=true)
        public Id recordId;

    }

    public class Response {

        @InvocableVariable
        public String status;

        @InvocableVariable
        public String jobId;

    }

    @InvocableMethod(label='Generate Lead Intake Recommended Action using Claude')
    public static List<Response> analyze(List<Request> requests) {

        System.debug('========== LeadIntakeRecommendedActions Started ==========');

        List<Response> responses = new List<Response>();

        System.debug('Request Count = ' + (requests == null ? 0 : requests.size()));

        if(requests == null || requests.isEmpty()){

            Response r = new Response();
            r.status = 'No Requests Received';
            responses.add(r);

            return responses;
        }

        for(Request req : requests){

            Response res = new Response();

            try{

                System.debug('----------------------------------------');
                System.debug('Processing Record Id: ' + req.recordId);

                if(req.recordId == null){

                    res.status = 'Record Id is NULL';
                    responses.add(res);
                    continue;

                }

                LeadRecommendedActionQueueable job =
                    new LeadRecommendedActionQueueable(req.recordId);

                System.debug('Queueable Instance Created');

                Id jobId = System.enqueueJob(job);

                System.debug('QUEUEABLE JOB ID = ' + jobId);

                res.jobId = String.valueOf(jobId);
                res.status = 'Queue Submitted Successfully';

            }
            catch(Exception ex){

                System.debug('******** EXCEPTION ********');
                System.debug('Type : ' + ex.getTypeName());
                System.debug('Message : ' + ex.getMessage());
                System.debug('Line : ' + ex.getLineNumber());
                System.debug(ex.getStackTraceString());

                res.status =
                    'Error : ' +
                    ex.getMessage() +
                    ' (Line ' +
                    ex.getLineNumber() +
                    ')';

            }

            responses.add(res);

        }

        System.debug('========== LeadIntakeRecommendedActions Finished ==========');

        return responses;

    }

}