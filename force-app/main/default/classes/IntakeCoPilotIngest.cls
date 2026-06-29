/**
 * REST entry point the AWS co-pilot service posts to during a live call.
 * One POST = one turn (or one system signal). Publishes a Co_Pilot_Event__e
 * that the intakeCoPilot LWC is subscribed to via empApi.
 *
 *   POST /services/apexrest/copilot/v1/turn
 *   {
 *     "intakeId": "a01...",
 *     "turnType": "client",
 *     "transcript": "...",          // spoken-language verbatim
 *     "translation": "...",         // English, blank if already English
 *     "detectedLanguage": "es",
 *     "suggestion": "...",          // Claude guidance (may be blank on a pure transcript turn)
 *     "sentiment": "Negative",
 *     "leadFit": "Strong",
 *     "sequence": 7
 *   }
 *
 * Auth: the AWS service authenticates as an integration user via a Connected App
 * (OAuth client-credentials / JWT). No API key logic lives here.
 */
@RestResource(urlMapping='/copilot/v1/*')
global with sharing class IntakeCoPilotIngest {

    global class TurnPayload {
        global String intakeId;
        global String turnType;
        global String transcript;
        global String translation;
        global String detectedLanguage;
        global String suggestion;
        global String sentiment;
        global String leadFit;
        global Decimal sequence;
    }

    global class IngestResult {
        global Boolean success;
        global String message;
    }

    @HttpPost
    global static IngestResult publishTurn() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        IngestResult result = new IngestResult();

        TurnPayload payload;
        try {
            payload = (TurnPayload) JSON.deserialize(
                req.requestBody.toString(), TurnPayload.class);
        } catch (Exception e) {
            res.statusCode = 400;
            result.success = false;
            result.message = 'Malformed JSON: ' + e.getMessage();
            return result;
        }

        if (payload == null || String.isBlank(payload.intakeId)) {
            res.statusCode = 400;
            result.success = false;
            result.message = 'intakeId is required.';
            return result;
        }

        Co_Pilot_Event__e evt = new Co_Pilot_Event__e(
            Intake_Id__c         = payload.intakeId,
            Turn_Type__c         = payload.turnType,
            Transcript__c        = payload.transcript,
            Translation__c       = payload.translation,
            Detected_Language__c = payload.detectedLanguage,
            Suggestion__c        = payload.suggestion,
            Sentiment__c         = payload.sentiment,
            Lead_Fit__c          = payload.leadFit,
            Sequence__c          = payload.sequence
        );

        Database.SaveResult sr = EventBus.publish(evt);
        if (sr.isSuccess()) {
            res.statusCode = 202; // accepted; delivery is async to subscribers
            result.success = true;
            result.message = 'published';
        } else {
            res.statusCode = 500;
            result.success = false;
            String msg = '';
            for (Database.Error err : sr.getErrors()) {
                msg += err.getMessage() + ' ';
            }
            result.message = msg;
        }
        return result;
    }
}