/**
 * Projects signings + value for 30/60/90-day horizons from the current open pipeline and the
 * historical per-stage sign rates. Confidence bands come from the binomial variance of those
 * rates (widen when history is thin). Claude narrates the drivers; the number-set guardrail
 * rejects any figure it didn't get from the model, falling back to a deterministic template.
 */
public with sharing class ConversionForecastService {

    private static final List<Integer> HORIZONS = new List<Integer>{ 30, 60, 90 };
    private static final Integer MAX_TOKENS = 700;
    private static final String NOTIF = 'Conversion_Forecast_Alert';
    private static final Decimal Z = 1.28; // ~80% confidence band half-width

    private static final String SYSTEM_PROMPT =
        'You are a revenue-intelligence assistant for a personal-injury law firm. You receive a ' +
        'pre-computed signings forecast and explain the drivers for the firm owner. STRICT RULE: ' +
        'only use the exact numbers provided. Never compute, sum, round, or invent a number. ' +
        'Keep it under 180 words.';

    public class NarrationOut {
        public String text;
        public String source; // 'AI' | 'Template'
    }

    public static Id enqueue() {
        return System.enqueueJob(new ConversionForecastJob());
    }

    public static List<Conversion_Forecast__c> run() {
        Integer windowDays = WinLossConfig.lookbackDays();
        ConversionRateService.Rates rates = ConversionRateService.compute(windowDays);

        List<Intake__c> open = [
            SELECT Status__c, Incident_Type__c
            FROM Intake__c
            WHERE Status__c != null AND Status__c NOT IN :ConversionRateService.CLOSED
        ];

        Decimal expSigned = 0, expValue = 0, variance = 0;
        for (Intake__c i : open) {
            Decimal p = rates.signRate.containsKey(i.Status__c) ? rates.signRate.get(i.Status__c) : 0;
            Decimal ev = RevenueLeakValuationService.value(i.Incident_Type__c).expectedValue;
            if (ev == null) ev = 0;
            expSigned += p;
            expValue += p * ev;
            variance += p * (1 - p);
        }
        Decimal sd = Decimal.valueOf(Math.sqrt(variance.doubleValue()));
        Decimal avgCycle = (rates.avgCycleDays == null || rates.avgCycleDays <= 0) ? 30 : rates.avgCycleDays;

        Date today = Date.today();
        List<Conversion_Forecast__c> fcs = new List<Conversion_Forecast__c>();
        for (Integer h : HORIZONS) {
            Decimal ratio = Decimal.valueOf(h) / avgCycle;
            Decimal factor = ratio > 1 ? 1 : ratio;
            Decimal pSigned = expSigned * factor;
            Decimal sdH = sd * factor;
            Integer lowV = asInt(pSigned - Z * sdH);
            Conversion_Forecast__c f = new Conversion_Forecast__c(
                Period_Start__c = today,
                Period_End__c = today.addDays(h),
                Horizon_Days__c = h,
                Projected_Signed__c = asInt(pSigned),
                Projected_Value__c = (expValue * factor).setScale(2, System.RoundingMode.HALF_UP),
                Confidence_Low__c = lowV < 0 ? 0 : lowV,
                Confidence_High__c = asInt(pSigned + Z * sdH),
                Guardrail_Status__c = 'Template',
                Generated_At__c = System.now(),
                Owner_User__c = WinLossConfig.ownerUserId()
            );
            fcs.add(f);
        }

        NarrationOut n = narrate(fcs, open.size(), rates);
        for (Conversion_Forecast__c f : fcs) {
            f.Narrative__c = n.text;
            f.Guardrail_Status__c = n.source;
        }
        insert fcs;
        deliver(fcs, n);
        return fcs;
    }

    // ── narration + guardrail ────────────────────────────────────────
    private static NarrationOut narrate(List<Conversion_Forecast__c> fcs, Integer openCount, ConversionRateService.Rates rates) {
        NarrationOut out = new NarrationOut();
        out.source = 'Template';
        out.text = template(fcs, openCount);

        Set<Integer> allowed = new Set<Integer>();
        allowed.add(openCount);
        for (Conversion_Forecast__c f : fcs) {
            allowed.add(intOf(f.Projected_Signed__c));
            allowed.add(intOf(f.Confidence_Low__c));
            allowed.add(intOf(f.Confidence_High__c));
            allowed.add(intOf(f.Horizon_Days__c));
            allowed.add(f.Projected_Value__c.setScale(0, System.RoundingMode.HALF_UP).intValue());
        }
        for (String s : rates.signRate.keySet()) {
            allowed.add((rates.signRate.get(s) * 100).setScale(0, System.RoundingMode.HALF_UP).intValue());
            allowed.add(rates.sample.get(s));
        }

        try {
            AnthropicCalloutService.Result ai = AnthropicCalloutService.complete(
                WinLossConfig.model(), MAX_TOKENS, SYSTEM_PROMPT, buildPrompt(fcs, openCount, rates));
            if (guardrailPasses(ai.text, allowed)) {
                out.text = ai.text.trim();
                out.source = 'AI';
            }
        } catch (Exception e) {
            // keep template
        }
        return out;
    }

    @TestVisible
    private static Boolean guardrailPasses(String text, Set<Integer> allowed) {
        if (String.isBlank(text)) return false;
        String t = text.replaceAll(',', ''); // so 1,250 reads as 1250
        Matcher pm = Pattern.compile('([0-9]+)\\s*%').matcher(t);
        while (pm.find()) {
            if (!allowed.contains(Integer.valueOf(pm.group(1)))) return false;
        }
        Matcher im = Pattern.compile('\\b([0-9]{2,})\\b').matcher(t);
        while (im.find()) {
            Integer v = Integer.valueOf(im.group(1));
            if (v >= 10 && !allowed.contains(v)) return false;
        }
        return true;
    }

    private static String buildPrompt(List<Conversion_Forecast__c> fcs, Integer openCount, ConversionRateService.Rates rates) {
        String s = 'Open pipeline: ' + openCount + ' intakes.\nProjected signings (with band) and value:\n';
        for (Conversion_Forecast__c f : fcs) {
            s += '  - next ' + intOf(f.Horizon_Days__c) + ' days: ' + intOf(f.Projected_Signed__c)
                + ' signings (band ' + intOf(f.Confidence_Low__c) + '-' + intOf(f.Confidence_High__c)
                + '), value ' + f.Projected_Value__c.setScale(0) + '\n';
        }
        s += 'Per-stage sign rates (rate%, sample):\n';
        for (String st : rates.signRate.keySet()) {
            s += '  - ' + st + ': ' + (rates.signRate.get(st) * 100).setScale(0) + '%, n=' + rates.sample.get(st) + '\n';
        }
        s += '\nExplain what is driving the forecast and where the risk is. Use only these numbers.';
        return s;
    }

    private static String template(List<Conversion_Forecast__c> fcs, Integer openCount) {
        String s = 'Forecast from ' + openCount + ' open intakes:\n';
        for (Conversion_Forecast__c f : fcs) {
            s += '- Next ' + intOf(f.Horizon_Days__c) + ' days: ~' + intOf(f.Projected_Signed__c)
                + ' signings (band ' + intOf(f.Confidence_Low__c) + '-' + intOf(f.Confidence_High__c)
                + '), ~$' + f.Projected_Value__c.setScale(0).format() + '.\n';
        }
        s += 'Bands widen when historical sample is thin.';
        return s;
    }

    // ── delivery ─────────────────────────────────────────────────────
    private static void deliver(List<Conversion_Forecast__c> fcs, NarrationOut n) {
        Conversion_Forecast__c ninety = fcs[fcs.size() - 1];
        Id ownerId = WinLossConfig.ownerUserId();

        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIF LIMIT 1
        ];
        if (!types.isEmpty()) {
            Messaging.CustomNotification cn = new Messaging.CustomNotification();
            cn.setTitle('Conversion forecast updated');
            cn.setBody('~' + intOf(ninety.Projected_Signed__c) + ' signings projected in the next 90 days.');
            cn.setNotificationTypeId(types[0].Id);
            cn.setTargetId(ninety.Id);
            try {
                cn.send(new Set<String>{ String.valueOf(ownerId) });
            } catch (Exception e) {}
        }

        if (WinLossConfig.sendEmail()) {
            List<User> us = [SELECT Email FROM User WHERE Id = :ownerId AND Email != null LIMIT 1];
            if (!us.isEmpty()) {
                Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                msg.setToAddresses(new List<String>{ us[0].Email });
                msg.setSubject('Conversion forecast');
                msg.setPlainTextBody(n.text);
                msg.setSaveAsActivity(false);
                try {
                    Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
                } catch (Exception e) {}
            }
        }
    }

    // ── helpers ──────────────────────────────────────────────────────
    private static Integer asInt(Decimal d) {
        return d.setScale(0, System.RoundingMode.HALF_UP).intValue();
    }
    private static Integer intOf(Decimal d) {
        return d == null ? 0 : d.intValue();
    }
}