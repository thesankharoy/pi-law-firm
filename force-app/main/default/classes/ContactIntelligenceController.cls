public with sharing class ContactIntelligenceController {
    @AuraEnabled
    public static ContactIntelligenceService.Recommendation getRecommendation(Id intakeId) {
        return ContactIntelligenceService.getRecommendation(intakeId);
    }

    @AuraEnabled
    public static ContactIntelligenceService.Recommendation refreshRecommendation(Id intakeId) {
        return ContactIntelligenceService.refreshRecommendation(intakeId);
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getIntakeTasks(Id intakeId) {
        return ContactIntelligenceService.getIntakeTasks(intakeId);
    }
}