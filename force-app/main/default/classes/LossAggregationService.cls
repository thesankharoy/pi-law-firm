/**
 * Deterministic aggregation of loss analyses over a lookback window. Every count, rate,
 * and "top" comes from SOQL here — the narration layer is only allowed to quote these.
 */
public with sharing class LossAggregationService {

    public class Aggregates {
        public Integer lookbackDays;
        public Integer total = 0;
        public Map<String, Integer> byFault = new Map<String, Integer>();
        public Map<String, Integer> byReason = new Map<String, Integer>();
        public Map<String, Integer> byObjection = new Map<String, Integer>();
        public Integer processCount = 0;
        public Integer processPct = 0;
        public String topReason;
        public Integer topReasonCount = 0;
        public String topObjection;
        public Integer topObjectionCount = 0;
    }

    public static Aggregates aggregate(Integer lookbackDays) {
        Aggregates a = new Aggregates();
        a.lookbackDays = lookbackDays;
        DateTime since = System.now().addDays(-lookbackDays);

        for (AggregateResult ar : [
            SELECT Fault_Category__c fc, COUNT(Id) c
            FROM Loss_Analysis__c
            WHERE CreatedDate >= :since
            GROUP BY Fault_Category__c
        ]) {
            String fc = (String) ar.get('fc');
            if (fc == null) fc = WinLossTaxonomy.FAULT_UNKNOWN;
            Integer c = (Integer) ar.get('c');
            a.byFault.put(fc, c);
            a.total += c;
            if (fc == 'Process') a.processCount = c;
        }

        for (AggregateResult ar : [
            SELECT Primary_Reason__c r, COUNT(Id) c
            FROM Loss_Analysis__c
            WHERE CreatedDate >= :since
            GROUP BY Primary_Reason__c
            ORDER BY COUNT(Id) DESC
        ]) {
            String r = (String) ar.get('r');
            if (r == null) r = WinLossTaxonomy.UNCLASSIFIED;
            Integer c = (Integer) ar.get('c');
            a.byReason.put(r, c);
            if (c > a.topReasonCount) { a.topReasonCount = c; a.topReason = r; }
        }

        for (AggregateResult ar : [
            SELECT Objection_Type__c o, COUNT(Id) c
            FROM Objection__c
            WHERE CreatedDate >= :since
            GROUP BY Objection_Type__c
            ORDER BY COUNT(Id) DESC
        ]) {
            String o = (String) ar.get('o');
            if (o == null) o = WinLossTaxonomy.OTHER_OBJECTION;
            Integer c = (Integer) ar.get('c');
            a.byObjection.put(o, c);
            if (c > a.topObjectionCount) { a.topObjectionCount = c; a.topObjection = o; }
        }

        a.processPct = a.total == 0 ? 0 : (a.processCount * 100) / a.total;
        return a;
    }
}