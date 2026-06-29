/**
 * Pure-arithmetic spend-shift what-if (US71-6): projects the net signed-case change from moving
 * a dollar amount from one source to another, using each source's historical cost-per-lead and
 * sign rate. No AI in the math — it's a transparent calculator.
 */
public with sharing class SourceSpendShiftCalculator {

    public class Result {
        @AuraEnabled public Decimal fromLost;
        @AuraEnabled public Decimal toGained;
        @AuraEnabled public Decimal net;
        @AuraEnabled public String explanation;
    }

    @AuraEnabled
    public static Result whatIf(String fromSource, String toSource, Decimal amount) {
        Result r = new Result();
        r.fromLost = 0;
        r.toGained = 0;
        if (amount == null) amount = 0;

        Map<String, Source_Quality_Snapshot__c> m = new Map<String, Source_Quality_Snapshot__c>();
        for (Source_Quality_Snapshot__c s : [
            SELECT Source__c, Cost_Per_Lead__c, Sign_Rate__c FROM Source_Quality_Snapshot__c
        ]) m.put(s.Source__c, s);

        Source_Quality_Snapshot__c f = m.get(fromSource);
        Source_Quality_Snapshot__c t = m.get(toSource);
        if (f != null && f.Cost_Per_Lead__c != null && f.Cost_Per_Lead__c > 0) {
            r.fromLost = ((amount / f.Cost_Per_Lead__c) * ((f.Sign_Rate__c == null ? 0 : f.Sign_Rate__c) / 100)).setScale(2);
        }
        if (t != null && t.Cost_Per_Lead__c != null && t.Cost_Per_Lead__c > 0) {
            r.toGained = ((amount / t.Cost_Per_Lead__c) * ((t.Sign_Rate__c == null ? 0 : t.Sign_Rate__c) / 100)).setScale(2);
        }
        r.net = (r.toGained - r.fromLost).setScale(2);
        r.explanation = 'Moving $' + amount + ' from ' + fromSource + ' to ' + toSource
            + ' projects a net ' + r.net + ' signed cases ('
            + r.toGained + ' gained, ' + r.fromLost + ' lost).';
        return r;
    }
}