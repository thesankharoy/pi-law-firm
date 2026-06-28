public with sharing class DripCampaignController {
    // ── Campaigns ─────────────────────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getCampaigns() {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (DripCampaign__c c : [
            SELECT Id, Name, Type__c, Total_Duration_Days__c, Active__c, Description__c, (SELECT Id FROM DripSteps__r)
            FROM DripCampaign__c
            ORDER BY Type__c ASC, Name ASC
        ]) {
            result.add(
                new Map<String, Object>{
                    'id' => c.Id,
                    'name' => c.Name,
                    'type' => c.Type__c,
                    'totalDays' => c.Total_Duration_Days__c,
                    'isActive' => c.Active__c,
                    'description' => c.Description__c,
                    'stepCount' => c.DripSteps__r != null ? c.DripSteps__r.size() : 0
                }
            );
        }
        return result;
    }

    @AuraEnabled
    public static String saveCampaign(String campaignJson) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(campaignJson);
        DripCampaign__c c = new DripCampaign__c();
        if (data.get('id') != null)
            c.Id = (Id) data.get('id');
        c.Name = (String) data.get('name');
        c.Type__c = (String) data.get('type');
        c.Total_Duration_Days__c = data.get('totalDays') != null
            ? Decimal.valueOf(String.valueOf(data.get('totalDays')))
            : 90;
        c.Active__c = data.get('isActive') != null ? (Boolean) data.get('isActive') : true;
        c.Description__c = (String) data.get('description');
        upsert c;
        return c.Id;
    }

    @AuraEnabled
    public static void deleteCampaign(Id campaignId) {
        delete [SELECT Id FROM DripCampaign__c WHERE Id = :campaignId LIMIT 1];
    }

    @AuraEnabled
    public static void toggleCampaignActive(Id campaignId, Boolean isActive) {
        update new DripCampaign__c(Id = campaignId, Active__c = isActive);
    }

    // ── Steps ─────────────────────────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getSteps(Id campaignId) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (DripStep__c s : [
            SELECT Id, Day_Number__c, Channel__c, Subject__c, Body__c, Task_Type__c, Sort_Order__c
            FROM DripStep__c
            WHERE DripCampaign__c = :campaignId
            ORDER BY Day_Number__c ASC, Sort_Order__c ASC
        ]) {
            result.add(
                new Map<String, Object>{
                    'id' => s.Id,
                    'dayNumber' => s.Day_Number__c,
                    'channel' => s.Channel__c,
                    'subject' => s.Subject__c,
                    'body' => s.Body__c,
                    'taskType' => s.Task_Type__c,
                    'sortOrder' => s.Sort_Order__c
                }
            );
        }
        return result;
    }

    @AuraEnabled
    public static String saveStep(Id campaignId, String stepJson) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(stepJson);
        DripStep__c s = new DripStep__c();
        if (data.get('id') != null)
            s.Id = (Id) data.get('id');
        s.DripCampaign__c = campaignId;
        s.Day_Number__c = data.get('dayNumber') != null ? Decimal.valueOf(String.valueOf(data.get('dayNumber'))) : 1;
        s.Channel__c = (String) data.get('channel');
        s.Subject__c = (String) data.get('subject');
        s.Body__c = (String) data.get('body');
        s.Task_Type__c = (String) data.get('taskType');
        s.Sort_Order__c = data.get('sortOrder') != null ? Decimal.valueOf(String.valueOf(data.get('sortOrder'))) : 0;
        upsert s;
        return s.Id;
    }

    @AuraEnabled
    public static void deleteStep(Id stepId) {
        delete [SELECT Id FROM DripStep__c WHERE Id = :stepId LIMIT 1];
    }

    // ── Enrollment (called from intakeDripStatus LWC) ─────────────
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getEnrollmentStatus(Id intakeId) {
        return DripCampaignService.getEnrollmentStatus(intakeId);
    }

    @AuraEnabled
    public static void deferIntake(Id intakeId, String reactivateDateStr) {
        DripCampaignService.deferIntake(intakeId, reactivateDateStr);
    }

    @AuraEnabled
    public static void cancelEnrollment(Id intakeId) {
        DripCampaignService.cancelEnrollmentForIntake(intakeId);
    }
}
