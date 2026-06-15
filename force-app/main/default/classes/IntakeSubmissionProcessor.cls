public without sharing class IntakeSubmissionProcessor implements Queueable {
    private List<IntakeWrapper> intakes;

    public IntakeSubmissionProcessor(List<IntakeWrapper> intakes) {
        this.intakes = intakes;
    }

    public void execute(QueueableContext ctx) {
        for (IntakeWrapper intake : intakes) {
            Savepoint sp = Database.setSavepoint();
            try {
                PartyIntakeService.process(intake);
            } catch (Exception e) {
                Database.rollback(sp); // undo partial Party/Intake/Role inserts for this one
                // No staging row to flag Failed — wire your own failure logging here
                // (Platform Event / error email) so the lead isn't lost silently.
                System.debug(
                    LoggingLevel.ERROR,
                    'Intake processing failed [' +
                        intake.submissionUuid +
                        ']: ' +
                        e.getMessage() +
                        ' | ' +
                        e.getStackTraceString()
                );
            }
        }
    }
}
