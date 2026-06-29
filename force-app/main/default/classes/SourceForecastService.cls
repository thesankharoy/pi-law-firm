/**
 * Projects next-period signed cases per source from historical sign rate x extrapolated lead
 * volume, with a deterministic binomial confidence band. Claude writes the reallocation
 * recommendation; the number-set guardrail (comma-tolerant) rejects any invented figure and
 * falls back to a deterministic template.
 */
public with sharing class SourceForecastService {

    private static final Integer HORIZON = 90;
    private static final Decimal Z = 1.28;
    private static final Integer MAX_TOKENS = 700;
    private static final String NOTIF = 'Source_Quality_Alert';

    private static final String SYSTEM_PROMPT =
        'You are a revenue-intelligence assistant for a personal-injury law firm. You receive ' +
        'per-source performance figures and recommend where to scale or cut marketing budget. ' +
        'STRICT RULE: only use the exact numbers provided; never compute or invent a number. ' +
        'Name the trade-off. Under 180 words.';

    public class NarrationOut {
        public String text;
        public String source;
    }

    public static Id enqueue() {
        return System.enqueueJob(new SourceForecastJob());
    }

    public static List<Source_Forecast__c> run() {
        // Compute snapshots in memory so the Claude callout happens BEFORE any DML.
        List<Source_Quality_Snapshot__c> snaps = SourceRollupService.compute();
        Integer windowDays = WinLossConfig.lookbackDays();

        List<Source_Forecast__c> fcs = new List<Source_Forecast__c>();
        for (Source_Quality_Snapshot__c s : snaps) {
            Decimal pRate = (s.Sign_Rate__c == null ? 0 : s.Sign_Rate__c) / 100;
            Integer leadsN = s.Leads__c == null ? 0 : s.Leads__c.intValue();
            Decimal projLeads = windowDays == 0 ? 0 : (Decimal.valueOf(leadsN) * HORIZON / windowDays);
            Decimal projSigned = projLeads * pRate;
            Decimal sd = Decimal.valueOf(Math.sqrt((projLeads * pRate * (1 - pRate)).doubleValue()));
            Integer low = (projSigned - Z * sd).setScale(0, System.RoundingMode.HALF_UP).intValue();
            fcs.add(new Source_Forecast__c(
                Source__c = s.Source__c, Horizon_Days__c = HORIZON,
                Projected_Signed__c = projSigned.setScale(0, System.RoundingMode.HALF_UP).intValue(),
                Confidence_Low__c = low < 0 ? 0 : low,
                Confidence_High__c = (projSigned + Z * sd).setScale(0, System.RoundingMode.HALF_UP).intValue(),
                Guardrail_Status__c = 'Template', Generated_At__c = System.now(),
                Owner_User__c = WinLossConfig.ownerUserId()));
        }

        NarrationOut n = narrate(snaps, fcs); // callout — still no DML done yet
        for (Source_Forecast__c f : fcs) {
            f.Narrative__c = n.text;
            f.Guardrail_Status__c = n.source;
        }
        // All DML now, after the callout.
        delete [SELECT Id FROM Source_Quality_Snapshot__c];
        if (!snaps.isEmpty()) insert snaps;
        insert fcs;
        deliver(fcs, n);
        return fcs;
    }

    private static NarrationOut narrate(List<Source_Quality_Snapshot__c> snaps, List<Source_Forecast__c> fcs) {
        NarrationOut out = new NarrationOut();
        out.source = 'Template';
        out.text = template(snaps, fcs);
        if (snaps.isEmpty()) return out;

        Set<Integer> allowed = new Set<Integer>();
        allowed.add(HORIZON);
        for (Source_Quality_Snapshot__c s : snaps) {
            allowed.add(intOf(s.Sign_Rate__c));
            allowed.add(intOf(s.Lead_Fit_Rate__c));
            allowed.add(intOf(s.Leads__c));
            allowed.add(intOf(s.Signed__c));
            allowed.add(intOf(s.Quality_Score__c));
            if (s.Cost_Per_Lead__c != null) allowed.add(intOf(s.Cost_Per_Lead__c));
            if (s.Cost_Per_Signed__c != null) allowed.add(intOf(s.Cost_Per_Signed__c));
            if (s.Avg_Case_Value__c != null) allowed.add(s.Avg_Case_Value__c.setScale(0, System.RoundingMode.HALF_UP).intValue());
        }
        for (Source_Forecast__c f : fcs) {
            allowed.add(intOf(f.Projected_Signed__c));
            allowed.add(intOf(f.Confidence_Low__c));
            allowed.add(intOf(f.Confidence_High__c));
        }

        try {
            AnthropicCalloutService.Result ai = AnthropicCalloutService.complete(
                WinLossConfig.model(), MAX_TOKENS, SYSTEM_PROMPT, buildPrompt(snaps, fcs));
            if (guardrailPasses(ai.text, allowed)) {
                out.text = ai.text.trim();
                out.source = 'AI';
            }
        } catch (Exception e) {}
        return out;
    }

    @TestVisible
    private static Boolean guardrailPasses(String text, Set<Integer> allowed) {
        if (String.isBlank(text)) return false;
        String t = text.replaceAll(',', '');
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

    private static String buildPrompt(List<Source_Quality_Snapshot__c> snaps, List<Source_Forecast__c> fcs) {
        Map<String, Source_Forecast__c> fByS = new Map<String, Source_Forecast__c>();
        for (Source_Forecast__c f : fcs) fByS.put(f.Source__c, f);
        String s = 'Per-source performance (window):\n';
        for (Source_Quality_Snapshot__c q : snaps) {
            Source_Forecast__c f = fByS.get(q.Source__c);
            s += '  - ' + q.Source__c + ': ' + intOf(q.Leads__c) + ' leads, ' + intOf(q.Signed__c)
                + ' signed (' + intOf(q.Sign_Rate__c) + '%), '
                + (q.Cost_Per_Signed__c == null ? 'no cost data' : ('cost/signed ' + intOf(q.Cost_Per_Signed__c)))
                + ', quality score ' + intOf(q.Quality_Score__c)
                + (f == null ? '' : (', projected ' + intOf(f.Projected_Signed__c) + ' next ' + HORIZON + ' days')) + '\n';
        }
        s += '\nRank the sources and recommend where to scale and where to cut. Use only these numbers.';
        return s;
    }

    private static String template(List<Source_Quality_Snapshot__c> snaps, List<Source_Forecast__c> fcs) {
        if (snaps.isEmpty()) return 'No source data yet.';
        String s = 'Source quality (best by score first):\n';
        for (Source_Quality_Snapshot__c q : snaps) {
            s += '- ' + q.Source__c + ': ' + intOf(q.Sign_Rate__c) + '% sign rate, score ' + intOf(q.Quality_Score__c)
                + (q.Cost_Per_Signed__c == null ? '' : (', $' + intOf(q.Cost_Per_Signed__c) + '/signed')) + '.\n';
        }
        s += 'Scale the highest-score sources; review the lowest.';
        return s;
    }

    private static void deliver(List<Source_Forecast__c> fcs, NarrationOut n) {
        Id ownerId = WinLossConfig.ownerUserId();
        if (!fcs.isEmpty()) {
            List<CustomNotificationType> types = [
                SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIF LIMIT 1
            ];
            if (!types.isEmpty()) {
                Messaging.CustomNotification cn = new Messaging.CustomNotification();
                cn.setTitle('Source quality updated');
                cn.setBody('Per-source signing forecast and reallocation guidance are ready.');
                cn.setNotificationTypeId(types[0].Id);
                cn.setTargetId(fcs[0].Id);
                try { cn.send(new Set<String>{ String.valueOf(ownerId) }); } catch (Exception e) {}
            }
        }
        if (WinLossConfig.sendEmail()) {
            List<User> us = [SELECT Email FROM User WHERE Id = :ownerId AND Email != null LIMIT 1];
            if (!us.isEmpty()) {
                Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                msg.setToAddresses(new List<String>{ us[0].Email });
                msg.setSubject('Lead-source quality & reallocation');
                msg.setPlainTextBody(n.text);
                msg.setSaveAsActivity(false);
                try { Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg }); } catch (Exception e) {}
            }
        }
    }

    private static Integer intOf(Decimal d) {
        return d == null ? 0 : d.intValue();
    }
}