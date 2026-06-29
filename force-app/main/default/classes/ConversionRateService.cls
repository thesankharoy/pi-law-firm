/**
 * Deterministic conversion model derived from Stage_Transition__c over a rolling window:
 * per-stage sign-through rate (of closed intakes that reached the stage, the fraction that
 * signed), sample size, average dwell per stage, and the average sign cycle length.
 */
public with sharing class ConversionRateService {

    public static final Set<String> SIGNED = new Set<String>{ 'Retainer Agreement Signed', 'Converted' };
    public static final Set<String> CLOSED =
        new Set<String>{ 'Retainer Agreement Signed', 'Converted', 'Turned Down', 'Referred Out' };

    public class Rates {
        public Map<String, Decimal> signRate = new Map<String, Decimal>();
        public Map<String, Integer> sample = new Map<String, Integer>();
        public Map<String, Decimal> dwellDays = new Map<String, Decimal>();
        public Decimal avgCycleDays = 0;
    }

    public static Rates compute(Integer windowDays) {
        Rates r = new Rates();
        DateTime since = System.now().addDays(-windowDays);

        Map<Id, List<Stage_Transition__c>> byIntake = new Map<Id, List<Stage_Transition__c>>();
        Map<Id, String> curStatus = new Map<Id, String>();
        for (Stage_Transition__c t : [
            SELECT Intake__c, To_Status__c, Occurred_At__c, Intake__r.Status__c
            FROM Stage_Transition__c
            WHERE Occurred_At__c >= :since AND Intake__c != null
            ORDER BY Intake__c, Occurred_At__c ASC
        ]) {
            if (!byIntake.containsKey(t.Intake__c)) byIntake.put(t.Intake__c, new List<Stage_Transition__c>());
            byIntake.get(t.Intake__c).add(t);
            curStatus.put(t.Intake__c, t.Intake__r.Status__c);
        }

        Map<String, Integer> reached = new Map<String, Integer>();
        Map<String, Integer> signedCnt = new Map<String, Integer>();
        Map<String, Decimal> dwellSum = new Map<String, Decimal>();
        Map<String, Integer> dwellN = new Map<String, Integer>();
        List<Decimal> cycles = new List<Decimal>();

        for (Id iid : byIntake.keySet()) {
            List<Stage_Transition__c> seq = byIntake.get(iid);
            String cur = curStatus.get(iid);
            Boolean closed = CLOSED.contains(cur);
            Boolean isSigned = SIGNED.contains(cur);
            Set<String> stages = new Set<String>();
            DateTime firstAt = seq[0].Occurred_At__c;
            DateTime signedAt = null;

            for (Integer k = 0; k < seq.size(); k++) {
                String s = seq[k].To_Status__c;
                if (String.isBlank(s)) continue;
                stages.add(s);
                if (k < seq.size() - 1) {
                    Decimal d = (seq[k + 1].Occurred_At__c.getTime() - seq[k].Occurred_At__c.getTime()) / 86400000.0;
                    if (d >= 0) {
                        dwellSum.put(s, (dwellSum.containsKey(s) ? dwellSum.get(s) : 0) + d);
                        dwellN.put(s, (dwellN.containsKey(s) ? dwellN.get(s) : 0) + 1);
                    }
                }
                if (SIGNED.contains(s) && signedAt == null) signedAt = seq[k].Occurred_At__c;
            }

            if (closed) {
                for (String s : stages) {
                    reached.put(s, (reached.containsKey(s) ? reached.get(s) : 0) + 1);
                    if (isSigned) signedCnt.put(s, (signedCnt.containsKey(s) ? signedCnt.get(s) : 0) + 1);
                }
            }
            if (isSigned && signedAt != null) {
                Decimal cyc = (signedAt.getTime() - firstAt.getTime()) / 86400000.0;
                if (cyc >= 0) cycles.add(cyc);
            }
        }

        for (String s : reached.keySet()) {
            Integer n = reached.get(s);
            Integer sg = signedCnt.containsKey(s) ? signedCnt.get(s) : 0;
            r.sample.put(s, n);
            r.signRate.put(s, n == 0 ? 0 : (Decimal.valueOf(sg) / n).setScale(4));
        }
        for (String s : dwellSum.keySet()) {
            Integer n = dwellN.get(s);
            r.dwellDays.put(s, n == 0 ? 0 : (dwellSum.get(s) / n).setScale(1));
        }
        if (!cycles.isEmpty()) {
            Decimal sum = 0;
            for (Decimal c : cycles) sum += c;
            r.avgCycleDays = (sum / cycles.size()).setScale(1);
        }
        return r;
    }
}