global class PIEmailService implements Messaging.InboundEmailHandler {

global Messaging.InboundEmailResult handleInboundEmail(
    Messaging.InboundEmail email,
    Messaging.InboundEnvelope envelope
) {

    Messaging.InboundEmailResult result =
        new Messaging.InboundEmailResult();

    try {

        String emailBody = '';

        if(email.plainTextBody != null){
            emailBody = email.plainTextBody;
        } else if(email.htmlBody != null){
            emailBody = email.htmlBody;
        }

        String senderEmail = envelope.fromAddress;

        Map<String, Object> flowInputs =
            new Map<String, Object>();

        flowInputs.put('varEmailBody', emailBody);
        flowInputs.put('varEmailAddress', senderEmail);

        Flow.Interview.PI_Email_Intake_Flow flowInterview =
            new Flow.Interview.PI_Email_Intake_Flow(flowInputs);

        flowInterview.start();

        result.success = true;

    } catch(Exception ex) {

        System.debug('Email Service Error: ' + ex.getMessage());

        result.success = false;
    }

    return result;
}

}