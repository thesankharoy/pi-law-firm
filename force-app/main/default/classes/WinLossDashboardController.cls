/**
 * Read/UI controller for the Win/Loss owner surfaces:
 *  - getLossSummary: the "Why we lose" breakdown (fault split, top reasons, top objections).
 *  - getNeedsReview: low-confidence / unverified classifications awaiting a human check.
 *  - markReviewed: clears the Needs Review flag after a human confirms.
 */
public with sharing class WinLossDashboardController {

    public class Bucket implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public Integer count;
        @AuraEnabled public Integer pct;
        public Integer compareTo(Object o) {
            return ((Bucket) o).count - this.count; // descending
        }
    }

    public class LossSummary {
        @AuraEnabled public Integer lookbackDays;
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Integer processCount = 0;
        @AuraEnabled public Integer processPct = 0;
        @AuraEnabled public List<Bucket> faults = new List<Bucket>();
        @AuraEnabled public List<Bucket> reasons = new List<Bucket>();
        @AuraEnabled public List<Bucket> objections = new List<Bucket>();
    }

    public class ReviewRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id intakeId;
        @AuraEnabled public String intakeName;
        @AuraEnabled public String reason;
        @AuraEnabled public String fault;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String evidence;
        @AuraEnabled public String summary;
    }

    @AuraEnabled(cacheable=true)
    public static LossSummary getLossSummary(Integer lookbackDays) {
        Integer days = (lookbackDays == null || lookbackDays < 1) ? WinLossConfig.lookbackDays() : lookbackDays;
        LossAggregationService.Aggregates a = LossAggregationService.aggregate(days);

        LossSummary s = new LossSummary();
        s.lookbackDays = days;
        s.total = a.total;
        s.processCount = a.processCount;
        s.processPct = a.processPct;
        s.faults = buckets(a.byFault, a.total, null);
        s.reasons = buckets(a.byReason, a.total, 5);
        s.objections = buckets(a.byObjection, a.total, 5);
        return s;
    }

    @AuraEnabled(cacheable=true)
    public static List<ReviewRow> getNeedsReview() {
        List<ReviewRow> rows = new List<ReviewRow>();
        for (Loss_Analysis__c l : [
            SELECT Id, Intake__c, Intake__r.Name, Primary_Reason__c, Fault_Category__c,
                   Confidence__c, Evidence_Quote__c, Summary__c
            FROM Loss_Analysis__c
            WHERE Needs_Review__c = true
            ORDER BY CreatedDate DESC
            LIMIT 100
        ]) {
            ReviewRow r = new ReviewRow();
            r.id = l.Id;
            r.intakeId = l.Intake__c;
            r.intakeName = l.Intake__r != null ? l.Intake__r.Name : null;
            r.reason = prettify(l.Primary_Reason__c);
            r.fault = prettify(l.Fault_Category__c);
            r.confidence = l.Confidence__c;
            r.evidence = l.Evidence_Quote__c;
            r.summary = l.Summary__c;
            rows.add(r);
        }
        return rows;
    }

    @AuraEnabled
    public static void markReviewed(Id analysisId) {
        Loss_Analysis__c l = [
            SELECT Id, Needs_Review__c FROM Loss_Analysis__c WHERE Id = :analysisId LIMIT 1
        ];
        l.Needs_Review__c = false;
        update l;
    }

    // ── helpers ──────────────────────────────────────────────────────
    private static List<Bucket> buckets(Map<String, Integer> m, Integer total, Integer topN) {
        List<Bucket> result = new List<Bucket>();
        for (String k : m.keySet()) {
            Bucket b = new Bucket();
            b.label = prettify(k);
            b.count = m.get(k);
            b.pct = total == 0 ? 0 : (m.get(k) * 100) / total;
            result.add(b);
        }
        result.sort();
        if (topN != null && result.size() > topN) {
            List<Bucket> trimmed = new List<Bucket>();
            for (Integer i = 0; i < topN; i++) trimmed.add(result[i]);
            return trimmed;
        }
        return result;
    }

    private static String prettify(String s) {
        return String.isBlank(s) ? s : s.replace('_', ' ');
    }
}