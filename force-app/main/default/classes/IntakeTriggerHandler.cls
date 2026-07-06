public without sharing class IntakeTriggerHandler {
    public static final String STATUS_RETAINER_SIGNED = 'Retainer Agreement Signed';
    public static final String STATUS_TURNED_DOWN     = 'Turned Down';

    /**
     * BEFORE UPDATE — manage the doc-generation flag on the in-flight record.
     *  - Entering "Retainer Agreement Signed"  -> flag TRUE  (generate docs)
     *  - Entering "Turned Down"                 -> flag FALSE (cancel any pending
     *    generation, so a previously-signed-then-declined intake never generates)
     * No DML: assigned on the record already being saved.
     */
    public static void flagOnSigning(List<Intake__c> newList, Map<Id, Intake__c> oldMap) {
        for (Intake__c intake : newList) {
            Intake__c old = oldMap.get(intake.Id);
            Boolean enteredSigned    = intake.Status__c == STATUS_RETAINER_SIGNED && old.Status__c != STATUS_RETAINER_SIGNED;
            Boolean enteredTurnedDown= intake.Status__c == STATUS_TURNED_DOWN     && old.Status__c != STATUS_TURNED_DOWN;

            if (enteredSigned) {
                intake.Auth_Docs_Pending__c = true;
            } else if (enteredTurnedDown) {
                intake.Auth_Docs_Pending__c = false;   // client declined — cancel generation
            }
        }
    }

    /**
     * AFTER UPDATE — case-summary publish only.
     */
    public static void handleAfterUpdate(List<Intake__c> newList, Map<Id, Intake__c> oldMap) {
        List<Id> newlySignedIntakeIds = new List<Id>();
        for (Intake__c intake : newList) {
            Intake__c oldIntake = oldMap.get(intake.Id);
            if (intake.Status__c == STATUS_RETAINER_SIGNED
                && oldIntake.Status__c != STATUS_RETAINER_SIGNED) {
                newlySignedIntakeIds.add(intake.Id);
            }
        }
        if (!newlySignedIntakeIds.isEmpty()) {
            publishCaseSummary(newlySignedIntakeIds);
        }
    }

    private static void publishCaseSummary(List<Id> intakeIds) {
        List<Case_Summary_Generation__e> events = new List<Case_Summary_Generation__e>();
        for (Id intakeId : intakeIds) {
            events.add(new Case_Summary_Generation__e(Intake_Id__c = String.valueOf(intakeId)));
        }
        List<Database.SaveResult> results = EventBus.publish(events);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error err : results[i].getErrors()) {
                    System.debug(LoggingLevel.ERROR,
                        '[IntakeTriggerHandler] Case_Summary_Generation__e publish FAILED for '
                        + intakeIds[i] + ' — ' + err.getStatusCode() + ': ' + err.getMessage());
                }
            }
        }
    }
}