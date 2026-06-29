public without sharing class IntakeStatusUpdateController {

    public String intakeId    { get; set; }
    public String action      { get; set; }
    public String intakeName  { get; set; }
    public String newStatus   { get; set; }
    public String message     { get; set; }
    public Boolean isSuccess  { get; set; }
    public Boolean isError    { get; set; }

    // ─── Constructor ─────────────────────────────────────────────────
    public IntakeStatusUpdateController() {
        this.isSuccess = false;
        this.isError   = false;

        this.intakeId = ApexPages.currentPage().getParameters().get('id');
        this.action   = ApexPages.currentPage().getParameters().get('action');

        if (String.isBlank(this.intakeId) || String.isBlank(this.action)) {
            this.isError = true;
            this.message = 'Invalid request. Missing intake ID or action.';
            return;
        }

        Map<String, String> actionToStatus = new Map<String, String>{
            'Review'   => 'Under Review',
            'Approved' => 'Retainer Agreement Signed',
            'Rejected' => 'Turned Down'
        };

        if (!actionToStatus.containsKey(this.action)) {
            this.isError = true;
            this.message = 'Unknown action: ' + this.action;
            return;
        }

        this.newStatus = actionToStatus.get(this.action);

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

            // @future method se DML karo — Guest User restriction bypass
            IntakeStatusUpdateController.updateStatusAsync(this.intakeId, this.newStatus);

            this.isSuccess = true;
            this.message   = 'Status successfully updated to "' + this.newStatus + '".';

        } catch (Exception e) {
            this.isError = true;
            this.message = 'Error: ' + e.getMessage();
            System.debug('IntakeStatusUpdateController Error: ' + e.getMessage());
        }
    }

    // ─── @future method — DML runs in system context ──────────────────
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