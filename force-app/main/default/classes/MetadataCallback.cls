public class MetadataCallback implements Metadata.DeployCallback {
    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext ctx) {
        if (!result.status.equals(Metadata.DeployStatus.Succeeded)) {
            // Log failure — create a Platform Event or Custom Object error log
            System.debug('CMT Deploy FAILED: ' + result.errorMessage);
            // Optionally: insert error log record here
            Error_Log__c log = new Error_Log__c(
                Error_Label__c = 'CMT Deploy Failure',
                Message__c = result.errorMessage
            );
            insert log;
        }
    }
}
