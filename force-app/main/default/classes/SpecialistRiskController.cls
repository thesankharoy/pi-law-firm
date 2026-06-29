public with sharing class SpecialistRiskController {

    private static final Set<String> SIGNED_STATUSES = new Set<String>{
        'Retainer Agreement Signed', 'Converted'
    };

    // Same substantive-call gate as the speed-vs-skill dashboard
    private static final Integer MIN_CALL_SECS = 5;
    private static final Set<String> NO_CONNECT = new Set<String>{
        'No Answer', 'Busy', 'Left Voicemail', 'Wrong Number'
    };

    private static final Integer MIN_LEADS = 3;   // volume guard: ignore tiny samples
    private static final Decimal STABLE = 5;      // within +/- 5% counts as flat

    @AuraEnabled(cacheable=true)
    public static List<RiskRow> getSpecialistRisk(Integer windowDays) {
        if (windowDays == null || windowDays <= 0) {
            windowDays = 30;
        }
        DateTime recentStart = DateTime.now().addDays(-windowDays);        // recent window
        DateTime baseStart   = DateTime.now().addDays(-2 * windowDays);    // prior window start

        List<Intake__c> intakes = [
            SELECT Id, CreatedDate, Status__c
            FROM Intake__c
            WHERE CreatedDate >= :baseStart
            LIMIT 50000
        ];
        if (intakes.isEmpty()) {
            return new List<RiskRow>();
        }

        Map<Id, Intake__c> imap = new Map<Id, Intake__c>(intakes);

        // first substantive call per intake (drives owner, response time, QA)
        List<Task> tasks = [
            SELECT WhatId, OwnerId, Owner.Name, CreatedDate, Call_QA_Score__c
            FROM Task
            WHERE WhatId IN :imap.keySet()
            AND Status = 'Completed'
            AND (Subject LIKE 'Inbound Call%'OR Subject LIKE 'Outbound Call%')
            AND CallDurationInSeconds >= :MIN_CALL_SECS
            AND CallDisposition NOT IN :NO_CONNECT
            ORDER BY CreatedDate ASC
        ];
        Map<Id, Task> firstCall = new Map<Id, Task>();
        for (Task t : tasks) {
            if (t.WhatId != null && !firstCall.containsKey(t.WhatId)) {
                firstCall.put(t.WhatId, t);
            }
        }

        Map<Id, Acc> accs = new Map<Id, Acc>();
        for (Intake__c i : intakes) {
            Task fc = firstCall.get(i.Id);
            if (fc == null || fc.OwnerId == null ||
                !String.valueOf(fc.OwnerId).startsWith('005')) {
                continue;
            }
            Boolean recent = i.CreatedDate >= recentStart;
            Boolean signed = i.Status__c != null && SIGNED_STATUSES.contains(i.Status__c);
            Decimal mins = (fc.CreatedDate.getTime() - i.CreatedDate.getTime()) / 60000.0;
            if (mins < 0) mins = null;
            Decimal qa = fc.Call_QA_Score__c;

            Acc a = accs.get(fc.OwnerId);
            if (a == null) {
                a = new Acc();
                a.name = fc.Owner != null ? fc.Owner.Name : 'Specialist';
                accs.put(fc.OwnerId, a);
            }
            Win w = recent ? a.recentW : a.baseW;
            w.leads++;
            if (signed) w.signed++;
            if (qa != null)   { w.qaSum += qa;   w.qaCnt++; }
            if (mins != null) { w.minsSum += mins; w.minsCnt++; }
        }

        List<RiskRow> rows = new List<RiskRow>();
        for (Acc a : accs.values()) {
            if (a.recentW.leads < MIN_LEADS) continue;   // volume guard

            // performance change vs own baseline (+ = better, - = worse)
            Decimal qaCh   = relChange(a.recentW.avgQa(),   a.baseW.avgQa());     // higher better
            Decimal convCh = relChange(a.recentW.convRate(),a.baseW.convRate());  // higher better
            Decimal respRaw= relChange(a.recentW.avgMins(), a.baseW.avgMins());   // lower better...
            Decimal respCh = (respRaw == null) ? null : -respRaw;                 // ...so invert

            RiskRow r = new RiskRow();
            r.name = a.name;
            applyTrend(r, 'qa', qaCh);
            applyTrend(r, 'response', respCh);
            applyTrend(r, 'conversion', convCh);

            // risk tier from the three changes
            List<Decimal> ch = new List<Decimal>();
            if (qaCh   != null) ch.add(qaCh);
            if (respCh != null) ch.add(respCh);
            if (convCh != null) ch.add(convCh);

            Integer declines = 0;
            Decimal worst = 0;
            for (Decimal c : ch) {
                if (c <= -STABLE) declines++;
                if (c < worst) worst = c;
            }
            if (worst <= -10 || declines >= 2) {
                r.riskLevel = 'At Risk';  r.riskDotClass = 'dot risk-at';      r.rank = 0;
            } else if (worst <= -STABLE) {
                r.riskLevel = 'Watch';    r.riskDotClass = 'dot risk-watch';   r.rank = 1;
            } else {
                r.riskLevel = 'Healthy';  r.riskDotClass = 'dot risk-healthy'; r.rank = 2;
            }
            rows.add(r);
        }
        rows.sort();   // At Risk first, then Watch, then Healthy, then name
        return rows;
    }

    private static Decimal relChange(Decimal recent, Decimal base) {
        if (recent == null || base == null || base == 0) return null;
        return ((recent - base) / Math.abs(base) * 100).setScale(0);
    }

    private static void applyTrend(RiskRow r, String metric, Decimal change) {
        String text;
        String css;
        if (change == null) {
            text = '—'; css = 'trend tr-stable';
        } else if (Math.abs(change) < STABLE) {
            text = 'Stable'; css = 'trend tr-stable';
        } else if (change < 0) {
            text = '\u2193' + String.valueOf(Math.abs(change).intValue()) + '%';
            css = 'trend tr-down';
        } else {
            text = '\u2191' + String.valueOf(change.intValue()) + '%';
            css = 'trend tr-up';
        }
        if (metric == 'qa')              { r.qaText = text; r.qaClass = css; }
        else if (metric == 'response')   { r.responseText = text; r.responseClass = css; }
        else                             { r.conversionText = text; r.conversionClass = css; }
    }

    public class RiskRow implements Comparable {
        @AuraEnabled public String name;
        @AuraEnabled public String riskLevel;
        @AuraEnabled public String riskDotClass;
        @AuraEnabled public String qaText;          @AuraEnabled public String qaClass;
        @AuraEnabled public String responseText;    @AuraEnabled public String responseClass;
        @AuraEnabled public String conversionText;  @AuraEnabled public String conversionClass;
        public Integer rank;
        public Integer compareTo(Object o) {
            RiskRow b = (RiskRow) o;
            if (this.rank != b.rank) return this.rank - b.rank;
            return this.name.compareTo(b.name);
        }
    }

    class Win {
        Integer leads = 0;
        Integer signed = 0;
        Decimal qaSum = 0;   Integer qaCnt = 0;
        Decimal minsSum = 0; Integer minsCnt = 0;
        Decimal avgQa()    { return qaCnt == 0 ? null : qaSum / qaCnt; }
        Decimal avgMins()  { return minsCnt == 0 ? null : minsSum / minsCnt; }
        Decimal convRate() { return leads == 0 ? null : Decimal.valueOf(signed) * 100 / leads; }
    }
    class Acc {
        String name;
        Win recentW = new Win();
        Win baseW = new Win();
    }
}