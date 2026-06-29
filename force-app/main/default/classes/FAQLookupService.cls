/**
 * Plug-in lookup for the cross-module consumers (US72-6 live workspace, US72-7 coaching):
 * returns the best Approved entry for a detected objection type. Those modules aren't built
 * here, but they can call this the moment they exist.
 */
public with sharing class FAQLookupService {

    @AuraEnabled(cacheable=true)
    public static FAQ_Entry__c getApprovedForObjection(String objectionType) {
        if (String.isBlank(objectionType)) return null;
        List<FAQ_Entry__c> entries = [
            SELECT Id, Title__c, Recommended_Response__c, Objection_Type__c,
                   Handled_Success_Rate__c, Frequency__c
            FROM FAQ_Entry__c
            WHERE Status__c = 'Approved' AND Objection_Type__c = :objectionType
            ORDER BY Frequency__c DESC NULLS LAST
            LIMIT 1
        ];
        return entries.isEmpty() ? null : entries[0];
    }
}