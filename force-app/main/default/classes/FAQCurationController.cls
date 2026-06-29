/**
 * Controller for the curation LWC. Lists drafts and coverage gaps, and handles the
 * approve / retire / edit transitions — each of which writes an immutable
 * FAQ_Entry_Version__c snapshot and bumps the version (US72-9 audit trail).
 */
public with sharing class FAQCurationController {

    public class EntryRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String category;
        @AuraEnabled public String objectionType;
        @AuraEnabled public Integer frequency;
        @AuraEnabled public Integer successRate;
        @AuraEnabled public String response;
        @AuraEnabled public String status;
        @AuraEnabled public Integer version;
    }

    @AuraEnabled(cacheable=true)
    public static List<EntryRow> getDrafts() {
        return rows([
            SELECT Id, Title__c, Category__c, Objection_Type__c, Frequency__c,
                   Handled_Success_Rate__c, Recommended_Response__c, Status__c, Version__c
            FROM FAQ_Entry__c
            WHERE Status__c = 'Draft'
            ORDER BY Frequency__c DESC NULLS LAST
            LIMIT 200
        ]);
    }

    @AuraEnabled(cacheable=true)
    public static List<EntryRow> getCoverageGaps() {
        return rows([
            SELECT Id, Title__c, Category__c, Objection_Type__c, Frequency__c,
                   Handled_Success_Rate__c, Recommended_Response__c, Status__c, Version__c
            FROM FAQ_Entry__c
            WHERE Status__c != 'Approved' AND Frequency__c >= :FAQService.minFrequency()
            ORDER BY Frequency__c DESC NULLS LAST
            LIMIT 200
        ]);
    }

    @AuraEnabled
    public static void approveEntry(Id entryId) {
        transition(entryId, 'Approved', null);
    }

    @AuraEnabled
    public static void retireEntry(Id entryId) {
        transition(entryId, 'Retired', null);
    }

    @AuraEnabled
    public static void updateResponse(Id entryId, String response) {
        transition(entryId, null, response);
    }

    private static void transition(Id entryId, String newStatus, String newResponse) {
        FAQ_Entry__c e = [
            SELECT Id, Recommended_Response__c, Status__c, Version__c
            FROM FAQ_Entry__c WHERE Id = :entryId LIMIT 1
        ];
        if (newResponse != null) e.Recommended_Response__c = newResponse;
        if (newStatus != null) {
            e.Status__c = newStatus;
            if (newStatus == 'Approved') {
                e.Approved_By__c = UserInfo.getUserId();
                e.Approved_At__c = System.now();
            }
        }
        Integer v = (e.Version__c == null ? 0 : e.Version__c.intValue()) + 1;
        e.Version__c = v;
        update e;

        insert new FAQ_Entry_Version__c(
            FAQ_Entry__c = e.Id,
            Version__c = v,
            Recommended_Response__c = e.Recommended_Response__c,
            Status__c = e.Status__c,
            Changed_By__c = UserInfo.getUserId(),
            Changed_At__c = System.now()
        );
    }

    private static List<EntryRow> rows(List<FAQ_Entry__c> es) {
        List<EntryRow> out = new List<EntryRow>();
        for (FAQ_Entry__c e : es) {
            EntryRow r = new EntryRow();
            r.id = e.Id;
            r.title = e.Title__c;
            r.category = e.Category__c;
            r.objectionType = e.Objection_Type__c;
            r.frequency = e.Frequency__c == null ? 0 : e.Frequency__c.intValue();
            r.successRate = e.Handled_Success_Rate__c == null ? 0 : e.Handled_Success_Rate__c.intValue();
            r.response = e.Recommended_Response__c;
            r.status = e.Status__c;
            r.version = e.Version__c == null ? 0 : e.Version__c.intValue();
            out.add(r);
        }
        return out;
    }
}