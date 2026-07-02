trigger DocumentTrigger on Document__c(before insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        // Any Document__c created without an explicit Folder__c — via
        // Flow automation, another Apex class, Data Loader, or the API
        // — is automatically routed to its Intake's root folder. See
        // DocumentFolderService.autoAssignRootFolder for the full
        // rationale. This is what makes files created outside the
        // intakeDocumentManager LWC actually show up in it.
        DocumentFolderService.autoAssignRootFolder(Trigger.new);
    }
}