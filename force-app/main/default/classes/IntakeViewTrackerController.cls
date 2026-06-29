public with sharing class IntakeViewTrackerController {
    /**
     * Called once when the Intake record page loads.
     * Flips Assigned -> Working ONLY when the viewer is the current owner.
     * Re-checks status server-side so this is safe even if called multiple
     */
    @AuraEnabled
    public static void markWorkingIfOwner(Id intakeId) {
        if (intakeId == null)
            return;

        Intake__c i = [
            SELECT Id, OwnerId, Status__c
            FROM Intake__c
            WHERE Id = :intakeId
            LIMIT 1
        ];

        Boolean isOwner = (i.OwnerId == UserInfo.getUserId());
        Boolean isAssigned = (i.Status__c == 'Assigned');

        if (isOwner && isAssigned) {
            i.Status__c = 'Working';
            update i;
        }
        // Any other case (not owner, already past Assigned) — silently do nothing.
    }
}