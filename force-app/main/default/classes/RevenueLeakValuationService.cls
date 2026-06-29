/**
 * Deterministic dollar valuation of a leak. Looks up the matter type in the
 * Case_Value__mdt table and returns gross expected fee, sign probability, and the
 * risk-adjusted estimate (expected x probability). The DeveloperName "Default" row
 * is the fallback when an incident type has no explicit row.
 *
 * Every figure Claude is later allowed to quote originates here.
 */
public with sharing class RevenueLeakValuationService {

    public class Valuation {
        public Decimal expectedValue;    // gross expected fee, dollars
        public Decimal signProbability;  // 0.00 - 1.00
        public Decimal estimatedValue;   // expectedValue x signProbability, 2dp
    }

    private static Map<String, Case_Value__mdt> byIncidentType;

    public static Valuation value(String incidentType) {
        loadTable();

        Case_Value__mdt row = null;
        if (String.isNotBlank(incidentType)) {
            row = byIncidentType.get(incidentType.toLowerCase());
        }
        if (row == null) {
            row = byIncidentType.get('default');
        }

        Decimal expected = (row != null && row.Expected_Value__c != null) ? row.Expected_Value__c : 0;
        Decimal prob = (row != null && row.Sign_Probability__c != null) ? row.Sign_Probability__c : 0;

        Valuation v = new Valuation();
        v.expectedValue = expected;
        v.signProbability = prob;
        v.estimatedValue = (expected * prob).setScale(2, System.RoundingMode.HALF_UP);
        return v;
    }

    private static void loadTable() {
        if (byIncidentType != null) return;
        byIncidentType = new Map<String, Case_Value__mdt>();
        for (Case_Value__mdt r : Case_Value__mdt.getAll().values()) {
            if (r.Incident_Type__c != null) {
                byIncidentType.put(r.Incident_Type__c.toLowerCase(), r);
            }
        }
    }
}