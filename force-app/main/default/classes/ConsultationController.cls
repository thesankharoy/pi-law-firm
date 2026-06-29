public with sharing class ConsultationController {
    @AuraEnabled(cacheable=false)
    public static ConsultationService.IntakeStatusDTO getIntakeStatus(Id intakeId) {
        return ConsultationService.getIntakeStatus(intakeId);
    }

    @AuraEnabled(cacheable=false)
    public static List<ConsultationService.ConsultationDTO> getConsultations(Id intakeId) {
        return ConsultationService.getConsultations(intakeId);
    }

    @AuraEnabled(cacheable=false)
    public static List<ConsultationService.AttorneyDTO> getAttorneys(Id intakeId) {
        return ConsultationService.getAttorneys(intakeId);
    }

    @AuraEnabled(cacheable=false)
    public static ConsultationService.ConflictResult checkConflict(
        Id attorneyId,
        String startIso,
        Integer durationMinutes
    ) {
        return ConsultationService.checkConflict(attorneyId, startIso, durationMinutes);
    }

    @AuraEnabled
    public static ConsultationService.ConsultationDTO book(String requestJson) {
        return ConsultationService.book(requestJson);
    }

    @AuraEnabled
    public static ConsultationService.ConsultationDTO reschedule(
        Id consultationId,
        String newStartIso,
        Integer durationMinutes
    ) {
        return ConsultationService.reschedule(consultationId, newStartIso, durationMinutes);
    }

    @AuraEnabled
    public static void cancel(Id consultationId, String reason) {
        ConsultationService.cancel(consultationId, reason);
    }

    @AuraEnabled
    public static void updateStatus(Id consultationId, String newStatus) {
        ConsultationService.updateStatus(consultationId, newStatus);
    }
}