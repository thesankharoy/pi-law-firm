public with sharing class HipaaAuthorizationController {

    public IntakeDocumentDataService.IntakeDocPacket packet { get; private set; }

    public HipaaAuthorizationController() {
        Id intakeId = ApexPages.currentPage().getParameters().get('Id');
        if (intakeId != null) {
            packet = IntakeDocumentDataService.buildPacket(intakeId);
        } else {
            packet = new IntakeDocumentDataService.IntakeDocPacket();
        }
    }

    public String getIncidentDateFormatted() {
        return formatDate(packet.incidentDate);
    }

    public String getDobFormatted() {
        return formatDate(packet.clientDob);
    }

    private String formatDate(Date d) {
        if (d == null) {
            return 'N/A';
        }
        return DateTime.newInstance(d, Time.newInstance(0,0,0,0)).format('MMMM d, yyyy');
    }
}