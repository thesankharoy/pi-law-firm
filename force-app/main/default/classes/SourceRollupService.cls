/**
 * Deterministic per-source rollup (US71-2/3): joins Intake__c (leads + signings),
 * Loss_Analysis__c (#69, for lead-fit) and Marketing_Spend__c (cost) by Source over the
 * rolling window, and writes one Source_Quality_Snapshot__c per source with a TRANSPARENT
 * quality score and a plain rationale of its inputs. Snapshots are rebuilt each run.
 */
public with sharing class SourceRollupService {

    /** Persisting wrapper: replace all snapshots with a freshly computed set. */
    public static List<Source_Quality_Snapshot__c> rebuild() {
        List<Source_Quality_Snapshot__c> out = compute();
        delete [SELECT Id FROM Source_Quality_Snapshot__c];
        if (!out.isEmpty()) insert out;
        return out;
    }

    /** Pure computation — returns unsaved snapshots so callers can call out before DML. */
    public static List<Source_Quality_Snapshot__c> compute() {
        Integer windowDays = WinLossConfig.lookbackDays();
        DateTime since = System.now().addDays(-windowDays);
        Date sinceDate = since.date();

        Map<String, Integer> leads = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Source__c src, COUNT(Id) c FROM Intake__c
            WHERE CreatedDate >= :since AND Source__c != null GROUP BY Source__c
        ]) leads.put((String) ar.get('src'), (Integer) ar.get('c'));

        Map<String, Integer> signed = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Source__c src, COUNT(Id) c FROM Intake__c
            WHERE CreatedDate >= :since AND Source__c != null AND Status__c IN :ConversionRateService.SIGNED
            GROUP BY Source__c
        ]) signed.put((String) ar.get('src'), (Integer) ar.get('c'));

        Map<String, Integer> caseMerits = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Source__c src, COUNT(Id) c FROM Loss_Analysis__c
            WHERE CreatedDate >= :since AND Source__c != null AND Fault_Category__c = 'Case_Merits'
            GROUP BY Source__c
        ]) caseMerits.put((String) ar.get('src'), (Integer) ar.get('c'));

        Map<String, Decimal> spend = new Map<String, Decimal>();
        for (AggregateResult ar : [
            SELECT Source__c src, SUM(Amount__c) s FROM Marketing_Spend__c
            WHERE Period_End__c >= :sinceDate AND Source__c != null GROUP BY Source__c
        ]) spend.put((String) ar.get('src'), (Decimal) ar.get('s'));

        Map<String, List<String>> signedTypes = new Map<String, List<String>>();
        for (Intake__c i : [
            SELECT Source__c, Incident_Type__c FROM Intake__c
            WHERE CreatedDate >= :since AND Source__c != null AND Status__c IN :ConversionRateService.SIGNED
        ]) {
            if (!signedTypes.containsKey(i.Source__c)) signedTypes.put(i.Source__c, new List<String>());
            signedTypes.get(i.Source__c).add(i.Incident_Type__c);
        }

        Date today = Date.today();
        List<Source_Quality_Snapshot__c> out = new List<Source_Quality_Snapshot__c>();
        for (String src : leads.keySet()) {
            Integer L = leads.get(src);
            Integer S = signed.containsKey(src) ? signed.get(src) : 0;
            Integer CM = caseMerits.containsKey(src) ? caseMerits.get(src) : 0;
            Decimal SP = spend.get(src);
            Decimal AV = avgValue(signedTypes.get(src));

            Decimal signRate = L == 0 ? 0 : (Decimal.valueOf(S) / L * 100).setScale(2);
            Decimal leadFit = L == 0 ? 0 : (Decimal.valueOf(L - CM) / L * 100).setScale(2);
            Decimal cpl = (SP != null && L > 0) ? (SP / L).setScale(2) : null;
            Decimal cps = (SP != null && S > 0) ? (SP / S).setScale(2) : null;
            Decimal expPerLead = (L == 0 ? 0 : (Decimal.valueOf(S) / L)) * AV;

            Decimal score;
            String rationale;
            if (cpl != null && cpl > 0) {
                score = (expPerLead / cpl).setScale(2);
                rationale = 'Sign rate ' + signRate + '%, avg value ' + AV.setScale(0)
                    + ', cost/lead ' + cpl.setScale(0) + ' -> expected $/lead ' + expPerLead.setScale(0)
                    + ', ROI ' + score + 'x.';
            } else {
                score = (expPerLead / 1000).setScale(2);
                rationale = 'Sign rate ' + signRate + '%, avg value ' + AV.setScale(0)
                    + ', expected $/lead ' + expPerLead.setScale(0)
                    + ' (no spend recorded; score = expected $/lead / 1000).';
            }

            out.add(new Source_Quality_Snapshot__c(
                Source__c = src, Period_Start__c = today.addDays(-windowDays), Period_End__c = today,
                Leads__c = L, Signed__c = S, Sign_Rate__c = signRate, Lead_Fit_Rate__c = leadFit,
                Cost_Per_Lead__c = cpl, Cost_Per_Signed__c = cps, Avg_Case_Value__c = AV,
                Quality_Score__c = score, Score_Rationale__c = rationale));
        }
        return out;
    }

    private static Decimal avgValue(List<String> types) {
        if (types == null || types.isEmpty()) {
            Decimal d = RevenueLeakValuationService.value(null).expectedValue;
            return d == null ? 0 : d;
        }
        Decimal sum = 0;
        Integer n = 0;
        for (String t : types) {
            Decimal ev = RevenueLeakValuationService.value(t).expectedValue;
            if (ev != null) { sum += ev; n++; }
        }
        return n == 0 ? 0 : (sum / n).setScale(2);
    }
}