public without sharing class LetterOfRepresentationController {

    public IntakeDocumentDataService.IntakeDocPacket packet { get; private set; }

    public LetterOfRepresentationController() {
        Id intakeId = ApexPages.currentPage().getParameters().get('Id');
        if (intakeId != null) {
            packet = IntakeDocumentDataService.buildPacket(intakeId);
        } else {
            packet = new IntakeDocumentDataService.IntakeDocPacket();
        }
    }

    public String getTodayFormatted() {
        return formatDate(packet.today);
    }

    public String getIncidentDateFormatted() {
        return formatDate(packet.incidentDate);
    }

    public String getSolFormatted() {
        return formatDate(packet.statuteOfLimitations);
    }

    public Boolean getShowSolNotice() {
        return packet.statuteOfLimitations != null;
    }

    // Gender-neutral pronoun text — no gender field is collected on Intake
    // intake at this stage of the schema, so we deliberately use neutral
    // language rather than guess from a name.
    public String getHimHerThem() {
        return 'them';
    }

    public String getHisHerTheir() {
        return 'their';
    }

    private String formatDate(Date d) {
        if (d == null) {
            return 'N/A';
        }
        return DateTime.newInstance(d, Time.newInstance(0,0,0,0)).format('MMMM d, yyyy');
    }
}