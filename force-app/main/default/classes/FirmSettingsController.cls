public with sharing class FirmSettingsController {
    // ── Intake Manager ─────────────────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getIntakeManager() {
        List<Intake_Manager__c> mgrs = [
            SELECT Id, User__c, User__r.Name, User__r.Email, User__r.SmallPhotoUrl, Active__c
            FROM Intake_Manager__c
            WHERE Active__c = TRUE
            LIMIT 1
        ];
        if (mgrs.isEmpty())
            return null;
        Intake_Manager__c m = mgrs[0];
        return new Map<String, Object>{
            'id' => m.Id,
            'userId' => m.User__c,
            'name' => m.User__r.Name,
            'email' => m.User__r.Email,
            'photoUrl' => m.User__r.SmallPhotoUrl
        };
    }

    @AuraEnabled
    public static void saveIntakeManager(String userId) {
        // Deactivate any existing managers
        List<Intake_Manager__c> existing = [SELECT Id FROM Intake_Manager__c WHERE Active__c = TRUE];
        for (Intake_Manager__c m : existing)
            m.Active__c = false;
        if (!existing.isEmpty())
            update existing;

        // Upsert on User__c
        Intake_Manager__c mgr = new Intake_Manager__c(User__c = (Id) userId, Active__c = true);
        insert mgr;
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, String>> searchUsers(String searchTerm) {
        String q = '%' + searchTerm.trim() + '%';
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (User u : [
            SELECT Id, Name, Email, SmallPhotoUrl
            FROM User
            WHERE IsActive = TRUE AND Name LIKE :q
            ORDER BY Name
            LIMIT 10
        ]) {
            result.add(
                new Map<String, String>{
                    'id' => u.Id,
                    'name' => u.Name,
                    'email' => u.Email,
                    'photoUrl' => u.SmallPhotoUrl
                }
            );
        }
        return result;
    }

    // ── Engagement Rules ───────────────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getEngagementRules() {
        List<Engagement_Rule__mdt> rules = [
            SELECT
                Warm_After_BH_Days__c,
                Cold_After_BH_Days__c,
                Dead_After_BH_Days__c,
                Escalate_After_BH_Days__c,
                Specialist_Notify_On_Cold__c,
                Active__c
            FROM Engagement_Rule__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (rules.isEmpty()) {
            return new Map<String, Object>{
                'warmAfterDays' => 1,
                'coldAfterDays' => 3,
                'deadAfterDays' => 7,
                'escalateAfterDays' => 2,
                'specialistNotify' => true,
                'active' => true
            };
        }
        Engagement_Rule__mdt r = rules[0];
        return new Map<String, Object>{
            'warmAfterDays' => r.Warm_After_BH_Days__c,
            'coldAfterDays' => r.Cold_After_BH_Days__c,
            'deadAfterDays' => r.Dead_After_BH_Days__c,
            'escalateAfterDays' => r.Escalate_After_BH_Days__c,
            'specialistNotify' => r.Specialist_Notify_On_Cold__c,
            'active' => r.Active__c
        };
    }

    @AuraEnabled
    public static String saveEngagementRules(String rulesJson) {
        Map<String, Object> rules = (Map<String, Object>) JSON.deserializeUntyped(rulesJson);

        Metadata.CustomMetadata md = new Metadata.CustomMetadata();
        md.fullName = 'Engagement_Rule.Default';
        md.label = 'Default';
        md.values = new List<Metadata.CustomMetadataValue>{
            makeField('Warm_After_BH_Days__c', rules.get('warmAfterDays')),
            makeField('Cold_After_BH_Days__c', rules.get('coldAfterDays')),
            makeField('Dead_After_BH_Days__c', rules.get('deadAfterDays')),
            makeField('Escalate_After_BH_Days__c', rules.get('escalateAfterDays')),
            makeField('Specialist_Notify_On_Cold__c', rules.get('specialistNotify')),
            makeField('Active__c', rules.get('active'))
        };

        Metadata.DeployContainer c = new Metadata.DeployContainer();
        c.addMetadata(md);
        return Metadata.Operations.enqueueDeployment(c, new MetadataCallback());
    }

    @AuraEnabled
    public static String checkDeployStatus(String jobId) {
        if (String.isBlank(jobId))
            throw new AuraHandledException('Invalid job Id.');
        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');
            req.setEndpoint('callout:Salesforce_NC/services/data/v66.0/tooling/sobjects/DeployRequest/' + jobId);

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() != 200) {
                throw new AuraHandledException('Status check failed (HTTP ' + res.getStatusCode() + ')');
            }
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String status = (String) body.get('Status');
            if (status == 'Succeeded')
                return 'Succeeded';
            if (status == 'Failed' || status == 'Canceled') {
                Object detail = body.get('StateDetail');
                throw new AuraHandledException(
                    'Deployment ' + status.toLowerCase() + (detail != null ? ': ' + detail : '.')
                );
            }
            return status;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Could not check status: ' + e.getMessage());
        }
    }

    private static Metadata.CustomMetadataValue makeField(String field, Object val) {
        Metadata.CustomMetadataValue f = new Metadata.CustomMetadataValue();
        f.field = field;
        f.value = val;
        return f;
    }
}
