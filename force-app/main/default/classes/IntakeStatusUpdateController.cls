public without sharing class IntakeStatusUpdateController {
    public String intakeId    { get; set; }
    public String action      { get; set; }
    public String intakeName  { get; set; }
    public String newStatus   { get; set; }
    public String message     { get; set; }
    public Boolean isSuccess  { get; set; }
    public Boolean isError    { get; set; }

    public IntakeStatusUpdateController() {
        this.isSuccess = false;
        this.isError   = false;

        this.intakeId = ApexPages.currentPage().getParameters().get('varIntakeId');
        String statusParam = ApexPages.currentPage().getParameters().get('varIntakeStatus');

        if (String.isBlank(this.intakeId) || String.isBlank(statusParam)) {
            this.isError = true;
            this.message = 'Invalid request. Missing intake ID or status.';
            return;
        }

        this.newStatus = statusParam;

        try {
            List<Intake__c> intakeList = [
                SELECT Id, Name, Status__c
                FROM Intake__c
                WHERE Id = :this.intakeId
                LIMIT 1
            ];
            if (intakeList.isEmpty()) {
                this.isError = true;
                this.message = 'Intake record not found.';
                return;
            }
            this.intakeName = intakeList[0].Name;

            IntakeStatusUpdateController.updateStatusAsync(this.intakeId, this.newStatus);
            this.isSuccess = true;
            this.message   = 'Status successfully updated to "' + this.newStatus + '".';
        } catch (Exception e) {
            this.isError = true;
            this.message = 'Error: ' + e.getMessage();
            System.debug('IntakeStatusUpdateController Error: ' + e.getMessage());
        }
    }

    @future
    public static void updateStatusAsync(String intakeId, String newStatus) {
        try {
            Intake__c intake = [
                SELECT Id, Status__c
                FROM Intake__c
                WHERE Id = :intakeId
                LIMIT 1
            ];
            intake.Status__c = newStatus;
            update intake;
        } catch (Exception e) {
            System.debug('updateStatusAsync Error: ' + e.getMessage());
        }
    }
}