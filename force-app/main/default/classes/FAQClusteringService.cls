/**
 * Deterministic clustering: groups FAQ_Candidate__c by Cluster_Key__c and upserts one
 * FAQ_Entry__c per cluster with frequency and handled-success rate. Existing approved
 * entries keep their response/status/version — only the metrics are refreshed.
 */
public with sharing class FAQClusteringService {

    private class Agg {
        Integer total = 0;
        Integer signed = 0;
        String kind;
        String objectionType;
        String sampleText;
    }

    public static void rebuild() {
        Map<String, Agg> byCluster = new Map<String, Agg>();

        for (FAQ_Candidate__c c : [
            SELECT Cluster_Key__c, Kind__c, Objection_Type__c, Led_To_Signing__c, Raw_Text__c
            FROM FAQ_Candidate__c
            WHERE Needs_Review__c = false AND Cluster_Key__c != null
        ]) {
            Agg a = byCluster.get(c.Cluster_Key__c);
            if (a == null) {
                a = new Agg();
                a.kind = c.Kind__c;
                a.objectionType = c.Objection_Type__c;
                a.sampleText = c.Raw_Text__c;
                byCluster.put(c.Cluster_Key__c, a);
            }
            a.total++;
            if (c.Led_To_Signing__c == true) a.signed++;
        }

        if (byCluster.isEmpty()) return;

        List<FAQ_Entry__c> toUpsert = new List<FAQ_Entry__c>();
        for (String key : byCluster.keySet()) {
            Agg a = byCluster.get(key);
            FAQ_Entry__c e = new FAQ_Entry__c();
            e.Cluster_Key__c = key;                 // external id → upsert match
            e.Category__c = a.kind;                 // Question / Objection
            e.Objection_Type__c = a.objectionType;
            e.Title__c = titleFor(a);
            e.Frequency__c = a.total;
            e.Handled_Success_Rate__c = a.total == 0 ? 0 : (a.signed * 100) / a.total;
            // Status/Recommended_Response/Version/Approved_* intentionally NOT set:
            // new rows default to Draft; existing rows keep their curated values.
            toUpsert.add(e);
        }
        upsert toUpsert Cluster_Key__c;
    }

    private static String titleFor(Agg a) {
        if (a.kind == 'Objection' && String.isNotBlank(a.objectionType)) {
            return 'Objection: ' + a.objectionType.replace('_', ' ');
        }
        String s = a.sampleText == null ? 'Question' : a.sampleText;
        return s.length() > 80 ? s.substring(0, 80) : s;
    }
}