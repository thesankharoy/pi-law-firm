/**
 * Full-pipeline test for the Unsigned-Retainer leak slice: detection, valuation,
 * the narration guardrail (pass + reject + error fallback), alert delivery, the
 * Alerted dedup flip, the queueables, the scheduler, and the entry service.
 *
 * Note: inserting Intake__c fires the existing IntakeTrigger. We use a non-New status
 * ("Retainer Agreement Sent") so the assignment handler is skipped. If your trigger
 * needs richer setup, swap the inline inserts for your TestDataFactory.
 */
@isTest
private class RevenueLeakSliceTest {

    private static final String SENT = 'Retainer Agreement Sent';

    // ── Helpers ──────────────────────────────────────────────────────
    private static String firstPicklistValue(Schema.SObjectField f) {
        for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues()) {
            if (e.isActive()) return e.getValue();
        }
        return null;
    }

    /** Record type that exposes the active-stage statuses (incl. "Retainer Agreement Sent"). */
    private static Id activeIntakeRtId() {
        Schema.RecordTypeInfo rti = Intake__c.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get('Active_Intake');
        return rti == null ? null : rti.getRecordTypeId();
    }

    /** Inserts an intake parked at "Retainer Agreement Sent", with the clock set N calendar days ago. */
    private static Intake__c sentIntake(Integer calendarDaysAgo) {
        Intake__c i = new Intake__c(
            RecordTypeId = activeIntakeRtId(),
            Status__c = SENT,
            Incident_Type__c = firstPicklistValue(Intake__c.Incident_Type__c),
            Retainer_Sent_At__c = System.now().addDays(-calendarDaysAgo)
        );
        insert i;
        return i;
    }

    /** Re-queries Open, not-yet-alerted leaks the same way the narration job does. */
    private static List<Revenue_Leak__c> openLeaks() {
        return [
            SELECT Id, Name, Intake__c, Leak_Type__c, Severity__c,
                   Estimated_Value__c, Expected_Case_Value__c, Sign_Probability__c, Days_Overdue__c,
                   Intake__r.Name, Intake__r.Incident_Type__c, Intake__r.Lead_Source_Channel__c,
                   Intake__r.Client__r.Name
            FROM Revenue_Leak__c
            WHERE Status__c = 'Open' AND Alerted__c = false
            ORDER BY Estimated_Value__c DESC NULLS LAST
        ];
    }

    private static String dollarToken(Decimal d) {
        return '$' + String.valueOf(d.setScale(0, System.RoundingMode.HALF_UP).longValue());
    }

    // ── Detection + valuation ────────────────────────────────────────
    @isTest
    static void testDetectsPastSla() {
        sentIntake(14); // ~10 business days, well past the 3-day SLA

        Test.startTest();
        List<Revenue_Leak__c> detected = RevenueLeakDetector.detectUnsignedRetainers();
        Test.stopTest();

        System.assertEquals(1, detected.size(), 'one leak should be detected');
        Revenue_Leak__c leak = [
            SELECT Status__c, Leak_Type__c, Estimated_Value__c, Expected_Case_Value__c,
                   Sign_Probability__c, Days_Overdue__c, Severity__c, Alerted__c, Detail__c
            FROM Revenue_Leak__c LIMIT 1
        ];
        System.assertEquals('Open', leak.Status__c);
        System.assertEquals('Unsigned Retainer', leak.Leak_Type__c);
        System.assert(leak.Estimated_Value__c > 0, 'valued');
        System.assert(leak.Days_Overdue__c >= 1, 'overdue counted');
        System.assertEquals(false, leak.Alerted__c, 'not yet alerted');
        System.assertNotEquals(null, leak.Severity__c, 'severity banded');
        System.assertNotEquals(null, leak.Detail__c, 'facts snapshot present');
    }

    @isTest
    static void testWithinSlaNotDetected() {
        sentIntake(0); // sent just now → 0 business days
        // Also a non-sent intake must be ignored entirely.
        Intake__c other = new Intake__c(
            Status__c = 'New',
            Incident_Type__c = firstPicklistValue(Intake__c.Incident_Type__c)
        );
        insert other;

        Test.startTest();
        List<Revenue_Leak__c> detected = RevenueLeakDetector.detectUnsignedRetainers();
        Test.stopTest();

        System.assertEquals(0, detected.size(), 'nothing past SLA yet');
        System.assertEquals(0, [SELECT COUNT() FROM Revenue_Leak__c]);
    }

    @isTest
    static void testNoDuplicateLeak() {
        sentIntake(14);
        Test.startTest();
        RevenueLeakDetector.detectUnsignedRetainers();
        List<Revenue_Leak__c> second = RevenueLeakDetector.detectUnsignedRetainers();
        Test.stopTest();

        System.assertEquals(0, second.size(), 'second run finds nothing new');
        System.assertEquals(1, [SELECT COUNT() FROM Revenue_Leak__c], 'still exactly one leak');
    }

    @isTest
    static void testValuationTableAndDefault() {
        // Unknown type falls back to the Default row (15000 x 0.60 = 9000).
        RevenueLeakValuationService.Valuation def =
            RevenueLeakValuationService.value('___no_such_type___');
        System.assertEquals(15000, def.expectedValue.intValue(), 'default expected value');
        System.assert(def.signProbability == 0.6, 'default sign prob');
        System.assertEquals(9000, def.estimatedValue.intValue(), 'default risk-adjusted value');

        // Named row resolves directly (25000 x 0.65 = 16250).
        RevenueLeakValuationService.Valuation auto =
            RevenueLeakValuationService.value('Auto Accident');
        System.assertEquals(16250, auto.estimatedValue.intValue(), 'auto-accident value');
    }

    @isTest
    static void testBusinessDaysHelper() {
        // Fri 2026-06-19 12:00 -> Mon 2026-06-22 12:00 = 1 business day (Sat/Sun skipped).
        DateTime fri = DateTime.newInstance(2026, 6, 19, 12, 0, 0);
        DateTime mon = DateTime.newInstance(2026, 6, 22, 12, 0, 0);
        System.assertEquals(1, RevenueLeakDetector.businessDaysBetween(fri, mon));
        System.assertEquals(0, RevenueLeakDetector.businessDaysBetween(mon, fri), 'reversed = 0');
    }

    // ── Narration guardrail ──────────────────────────────────────────
    @isTest
    static void testNarrationGuardrailAccepts() {
        sentIntake(14);
        RevenueLeakDetector.detectUnsignedRetainers();
        List<Revenue_Leak__c> leaks = openLeaks();
        Decimal est = leaks[0].Estimated_Value__c;

        // Claude quotes ONLY the figure we sent → accepted as AI.
        String aiText = 'Top priority: this retainer is worth ' + dollarToken(est)
            + ' in risk-adjusted value. Follow up today.';
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200, aiText));

        Test.startTest();
        RevenueLeakNarrationService.NarrationResult n =
            RevenueLeakNarrationService.narrate(leaks);
        Test.stopTest();

        System.assertEquals('AI', n.source, 'clean figures accepted');
        System.assert(n.narrative.contains(dollarToken(est)), 'AI narrative kept');
        System.assertNotEquals(null, n.model, 'model recorded');
        System.assertEquals(200, n.inputTokens, 'token usage captured');
    }

    @isTest
    static void testNarrationGuardrailRejectsInventedFigure() {
        sentIntake(14);
        RevenueLeakDetector.detectUnsignedRetainers();
        List<Revenue_Leak__c> leaks = openLeaks();

        // Claude invents a figure we never sent → discarded, template used.
        String aiText = 'This leak is actually worth $999999, act now!';
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200, aiText));

        Test.startTest();
        RevenueLeakNarrationService.NarrationResult n =
            RevenueLeakNarrationService.narrate(leaks);
        Test.stopTest();

        System.assertEquals('Template', n.source, 'invented figure rejected');
        System.assert(!n.narrative.contains('999999'), 'bogus figure not surfaced');
        System.assert(n.narrative.contains('$'), 'deterministic template used');
    }

    @isTest
    static void testNarrationFallsBackOnHttpError() {
        sentIntake(14);
        RevenueLeakDetector.detectUnsignedRetainers();
        List<Revenue_Leak__c> leaks = openLeaks();
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(400, null));

        Test.startTest();
        RevenueLeakNarrationService.NarrationResult n =
            RevenueLeakNarrationService.narrate(leaks);
        Test.stopTest();

        System.assertEquals('Template', n.source, 'HTTP error → template');
        System.assert(String.isNotBlank(n.narrative), 'narrative still produced');
    }

    // ── Alert delivery + dedup flip ──────────────────────────────────
    @isTest
    static void testAlertDeliveryFlipsLeaks() {
        sentIntake(14);
        RevenueLeakDetector.detectUnsignedRetainers();
        List<Revenue_Leak__c> leaks = openLeaks();

        Test.startTest();
        // No mock → callout fails → deterministic template path, then deliver.
        RevenueLeakNarrationService.NarrationResult n =
            RevenueLeakNarrationService.narrate(leaks);
        Leak_Alert__c alert = RevenueLeakAlertService.deliver(n);
        Test.stopTest();

        System.assertNotEquals(null, alert.Id, 'alert persisted');
        System.assertEquals(1, alert.Leak_Count__c.intValue());
        System.assert(alert.Total_Value__c > 0, 'total value set');
        System.assertEquals('Template', alert.Narrative_Source__c);

        Revenue_Leak__c flipped = [
            SELECT Status__c, Alerted__c, Alert__c FROM Revenue_Leak__c LIMIT 1
        ];
        System.assertEquals('Alerted', flipped.Status__c, 'status flipped');
        System.assertEquals(true, flipped.Alerted__c, 'alerted flag set');
        System.assertEquals(alert.Id, flipped.Alert__c, 'leak linked to digest');

        // The flipped leak must no longer be picked up by a subsequent run.
        System.assertEquals(0, openLeaks().size(), 'no open un-alerted leaks remain');
    }

    // ── Queueables, scheduler, entry service ─────────────────────────
    @isTest
    static void testDetectionJobCreatesLeak() {
        sentIntake(14);
        Test.startTest();
        System.enqueueJob(new RevenueLeakDetectionJob());
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Revenue_Leak__c], 'job detected the leak');
    }

    @isTest
    static void testNarrationJobEndToEnd() {
        sentIntake(14);
        RevenueLeakDetector.detectUnsignedRetainers();
        Decimal est = openLeaks()[0].Estimated_Value__c;
        String aiText = 'Single open leak worth ' + dollarToken(est) + '. Act now.';

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new AnthropicCalloutMock(200, aiText));
        System.enqueueJob(new RevenueLeakNarrationJob());
        Test.stopTest();

        Leak_Alert__c alert = [
            SELECT Leak_Count__c, Narrative_Source__c, Narrative__c FROM Leak_Alert__c LIMIT 1
        ];
        System.assertEquals(1, alert.Leak_Count__c.intValue());
        System.assertEquals('AI', alert.Narrative_Source__c, 'guardrail accepted clean AI output');
        System.assertEquals(1, [SELECT COUNT() FROM Revenue_Leak__c WHERE Alerted__c = true]);
    }

    @isTest
    static void testServiceRunEnqueues() {
        sentIntake(14);
        Test.startTest();
        Id jobId = RevenueLeakService.run();
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'detection job enqueued');
        System.assertEquals(1, [SELECT COUNT() FROM Revenue_Leak__c], 'run() detected the leak');
    }

    @isTest
    static void testSchedulerRuns() {
        sentIntake(14);
        Test.startTest();
        String cron = '0 0 0 1 1 ? 2042';
        String jobId = System.schedule('Leak Scan Test', cron, new RevenueLeakScheduler());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'scheduled without error');
    }
}