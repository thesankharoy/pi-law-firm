/**
 * Unsigned-Retainer leak detector. Finds intakes still sitting at
 * "Retainer Agreement Sent" past the business-day SLA, values each one, and inserts
 * an Open Revenue_Leak__c. Deterministic end to end — no AI, no callouts.
 *
 * Every other leak type reuses this skeleton; only the candidate WHERE clause and the
 * severity rule change.
 */
public with sharing class RevenueLeakDetector {

    private static final String LEAK_TYPE = 'Unsigned Retainer';
    private static final String RULE_DEV_NAME = 'Unsigned_Retainer';
    @TestVisible
    private static final String SENT_STATUS = 'Retainer Agreement Sent';
    private static final Integer DEFAULT_THRESHOLD_DAYS = 3;

    /** Detects, values, and inserts new unsigned-retainer leaks. Returns what it inserted. */
    public static List<Revenue_Leak__c> detectUnsignedRetainers() {
        Leak_Rule__mdt rule = Leak_Rule__mdt.getInstance(RULE_DEV_NAME);
        if (rule == null || rule.Is_Active__c != true) {
            return new List<Revenue_Leak__c>();
        }
        Integer thresholdDays = rule.Threshold_Days__c == null
            ? DEFAULT_THRESHOLD_DAYS
            : Integer.valueOf(rule.Threshold_Days__c);

        List<Intake__c> candidates = [
            SELECT Id, Name, Incident_Type__c, Retainer_Sent_At__c, OwnerId,
                   Client__c, Client__r.Name, Lead_Source_Channel__c
            FROM Intake__c
            WHERE Status__c = :SENT_STATUS AND Retainer_Sent_At__c != null
        ];
        if (candidates.isEmpty()) {
            return new List<Revenue_Leak__c>();
        }

        // Never double-flag an intake that already has a live leak of this type.
        Set<Id> alreadyFlagged = new Set<Id>();
        for (Revenue_Leak__c existing : [
            SELECT Intake__c
            FROM Revenue_Leak__c
            WHERE Leak_Type__c = :LEAK_TYPE
              AND Status__c IN ('Open', 'Alerted')
              AND Intake__c IN :candidates
        ]) {
            alreadyFlagged.add(existing.Intake__c);
        }

        DateTime now = System.now();
        List<Revenue_Leak__c> toInsert = new List<Revenue_Leak__c>();
        for (Intake__c i : candidates) {
            if (alreadyFlagged.contains(i.Id)) continue;

            Integer bizDays = businessDaysBetween(i.Retainer_Sent_At__c, now);
            if (bizDays < thresholdDays) continue;
            Integer overdue = bizDays - thresholdDays;

            RevenueLeakValuationService.Valuation v =
                RevenueLeakValuationService.value(i.Incident_Type__c);

            Revenue_Leak__c leak = new Revenue_Leak__c();
            leak.Intake__c = i.Id;
            leak.Leak_Type__c = LEAK_TYPE;
            leak.Status__c = 'Open';
            leak.Detected_At__c = now;
            leak.Days_Overdue__c = overdue;
            leak.Expected_Case_Value__c = v.expectedValue;
            leak.Sign_Probability__c = v.signProbability * 100; // store as percent
            leak.Estimated_Value__c = v.estimatedValue;
            leak.Severity__c = severity(v.estimatedValue, rule);
            leak.Alerted__c = false;
            leak.Detail__c = buildDetail(i, bizDays, overdue, v);
            toInsert.add(leak);
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        return toInsert;
    }

    // ── Severity banding ─────────────────────────────────────────────
    private static String severity(Decimal estimatedValue, Leak_Rule__mdt rule) {
        Decimal ev = estimatedValue == null ? 0 : estimatedValue;
        if (rule.Critical_Value_Threshold__c != null && ev >= rule.Critical_Value_Threshold__c) {
            return 'Critical';
        }
        if (rule.High_Value_Threshold__c != null && ev >= rule.High_Value_Threshold__c) {
            return 'High';
        }
        Decimal mediumFloor = rule.High_Value_Threshold__c != null
            ? rule.High_Value_Threshold__c / 2
            : 5000;
        return ev >= mediumFloor ? 'Medium' : 'Low';
    }

    // ── Business-day elapsed counter ─────────────────────────────────
    /**
     * Whole business days (Mon-Fri) strictly between the sent timestamp and now.
     * Weekday detection uses a fixed Sunday reference so it is locale/timezone safe.
     */
    @TestVisible
    private static Integer businessDaysBetween(DateTime fromDt, DateTime toDt) {
        if (fromDt == null || toDt == null || fromDt >= toDt) return 0;
        Date d = fromDt.date();
        Date stop = toDt.date();
        Integer count = 0;
        while (d < stop) {
            d = d.addDays(1);
            if (!isWeekend(d)) count++;
        }
        return count;
    }

    private static Boolean isWeekend(Date d) {
        Date sunday = Date.newInstance(1900, 1, 7); // known Sunday
        Integer dow = Math.mod(sunday.daysBetween(d), 7); // 0=Sun ... 6=Sat
        return dow == 0 || dow == 6;
    }

    // ── Deterministic facts snapshot ─────────────────────────────────
    private static String buildDetail(
        Intake__c i, Integer bizDays, Integer overdue, RevenueLeakValuationService.Valuation v
    ) {
        String client = (i.Client__r != null && i.Client__r.Name != null) ? i.Client__r.Name : 'Unknown client';
        return 'Intake ' + i.Name + ' (' + client + ') has sat at "' + SENT_STATUS + '" for '
            + bizDays + ' business day(s) — ' + overdue + ' past SLA. '
            + 'Matter type: ' + (String.isBlank(i.Incident_Type__c) ? 'Unspecified' : i.Incident_Type__c) + '. '
            + 'Expected fee ' + v.expectedValue + ', sign probability '
            + (v.signProbability * 100).setScale(0) + '%, risk-adjusted value ' + v.estimatedValue + '.';
    }
}