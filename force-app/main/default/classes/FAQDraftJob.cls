/**
 * Drafts recommended responses for the top Draft clusters that don't yet have one.
 * Reads first (no DML), makes the draft callouts, then updates — keeping callouts clean of DML.
 * Output is always a Draft for a human to approve.
 */
public with sharing class FAQDraftJob implements Queueable, Database.AllowsCallouts {

    private static final Integer MAX_DRAFTS_PER_RUN = 5;

    public void execute(QueueableContext ctx) {
        // Long-text fields can't be filtered in SOQL, so screen for "no response yet" in Apex.
        List<FAQ_Entry__c> drafts = new List<FAQ_Entry__c>();
        for (FAQ_Entry__c e : [
            SELECT Id, Title__c, Cluster_Key__c, Recommended_Response__c
            FROM FAQ_Entry__c
            WHERE Status__c = 'Draft' AND Frequency__c >= :FAQService.minFrequency()
            ORDER BY Frequency__c DESC NULLS LAST
            LIMIT 50
        ]) {
            if (String.isBlank(e.Recommended_Response__c)) drafts.add(e);
            if (drafts.size() >= MAX_DRAFTS_PER_RUN) break;
        }
        if (drafts.isEmpty()) return;

        Set<String> keys = new Set<String>();
        for (FAQ_Entry__c e : drafts) keys.add(e.Cluster_Key__c);

        Map<String, List<String>> winning = new Map<String, List<String>>();
        Map<String, List<String>> examples = new Map<String, List<String>>();
        for (FAQ_Candidate__c c : [
            SELECT Cluster_Key__c, Response_Given__c, Raw_Text__c, Led_To_Signing__c
            FROM FAQ_Candidate__c
            WHERE Cluster_Key__c IN :keys AND Needs_Review__c = false
        ]) {
            if (c.Led_To_Signing__c == true && String.isNotBlank(c.Response_Given__c)) {
                addCapped(winning, c.Cluster_Key__c, c.Response_Given__c);
            }
            if (String.isNotBlank(c.Raw_Text__c)) {
                addCapped(examples, c.Cluster_Key__c, c.Raw_Text__c);
            }
        }

        Map<Id, String> drafted = new Map<Id, String>();
        for (FAQ_Entry__c e : drafts) {
            try {
                String txt = FAQDraftService.draftResponse(
                    e.Title__c, winning.get(e.Cluster_Key__c), examples.get(e.Cluster_Key__c));
                if (String.isNotBlank(txt)) drafted.put(e.Id, txt);
            } catch (Exception ex) {
                // leave undrafted; next run retries
            }
        }
        if (drafted.isEmpty()) return;

        List<FAQ_Entry__c> upd = new List<FAQ_Entry__c>();
        for (Id id : drafted.keySet()) {
            upd.add(new FAQ_Entry__c(Id = id, Recommended_Response__c = drafted.get(id)));
        }
        update upd;
    }

    private static void addCapped(Map<String, List<String>> m, String key, String val) {
        if (!m.containsKey(key)) m.put(key, new List<String>());
        if (m.get(key).size() < 5) m.get(key).add(val);
    }
}