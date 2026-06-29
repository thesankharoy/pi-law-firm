public with sharing class IntakeTriggerHandler {

    public static final String STATUS_RETAINER_SIGNED = 'Retainer Agreement Signed';

    public static void handleAfterUpdate(List<Intake__c> newList, Map<Id, Intake__c> oldMap) {
        List<Id> newlySignedIntakeIds = new List<Id>();

        for (Intake__c intake : newList) {
            Intake__c oldIntake = oldMap.get(intake.Id);

            Boolean justEnteredSigned =
                intake.Status__c == STATUS_RETAINER_SIGNED &&
                oldIntake.Status__c != STATUS_RETAINER_SIGNED;

            if (justEnteredSigned) {
                newlySignedIntakeIds.add(intake.Id);
            }
        }

        if (!newlySignedIntakeIds.isEmpty()) {
            enqueueAuthDocGeneration(newlySignedIntakeIds);
            // notifyRetainerSigned(newlySignedIntakeIds); // existing call — left untouched, shown for reference
        }
    }

    /**
     * One Queueable job per Intake. Kept 1:1 rather than batching many
     * intakes into a single job so that one intake's PDF/S3 failure can
     * never affect another intake's documents, and so each job's retry
     * story is simple and isolated.
     */
    private static void enqueueAuthDocGeneration(List<Id> intakeIds) {
        for (Id intakeId : intakeIds) {
            System.enqueueJob(new GenerateIntakeAuthDocsQueueable(intakeId));
        }
    }
}