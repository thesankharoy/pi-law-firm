public with sharing class SpeedSkillDashboardController {

    private static final String OBJ = 'Intake__c';
    private static final String FLD_STATUS = 'Status__c';

    private static final Set<String> SIGNED_STATUSES = new Set<String>{
        'Retainer Agreement Signed',
        'Converted'
    };

    // Substantive-call gate — shared anchor for BOTH axes (speed + skill)
    private static final Integer MIN_CALL_SECS = 5;
    private static final Set<String> NO_CONNECT = new Set<String>{
        'No Answer', 'Busy', 'Left Voicemail', 'Wrong Number'
    };

    private static final Integer MAX_REPS = 8;

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboard(Integer days) {

        if (days == null || days <= 0) {
            days = 90;
        }

        DateTime startDt = DateTime.now().addDays(-days);

        List<Intake__c> intakes = [
            SELECT Id,
                   CreatedDate,
                   OwnerId,
                   Status__c
            FROM Intake__c
            WHERE CreatedDate >= :startDt
            LIMIT 50000
        ];

        if (intakes.isEmpty()) {
            return new DashboardData();
        }

        Map<Id, Intake__c> intakeMap = new Map<Id, Intake__c>(intakes);

        // First SUBSTANTIVE Twilio call per Intake (either direction).
        // Gate: connected (>= 30s) + real disposition. Excludes the missed inbound
        // call that created the intake, ring-outs and voicemails — so the speed axis
        // and the QA score both anchor to the same first REAL conversation.
        // Call_QA_Score__c lives on the Task (written by the Prompt Builder flow).
        List<Task> tasks = [
            SELECT Id,
                   WhatId,
                   OwnerId,
                   Owner.Name,
                   CreatedDate,
                   CallDurationInSeconds,
                   CallDisposition,
                   CallType,
                   Call_QA_Score__c
            FROM Task
            WHERE WhatId IN :intakeMap.keySet()
            AND Status = 'Completed'
           // AND Subject = 'Twilio Call'
            AND CallDurationInSeconds >= :MIN_CALL_SECS
            AND CallDisposition NOT IN :NO_CONNECT
            ORDER BY CreatedDate ASC
        ];

        Map<Id, Task> firstCallMap = new Map<Id, Task>();

        for (Task t : tasks) {
            if (t.WhatId != null && !firstCallMap.containsKey(t.WhatId)) {
                firstCallMap.put(t.WhatId, t);
            }
        }

        Map<String, Integer> spLeads = new Map<String, Integer>();
        Map<String, Integer> spSigned = new Map<String, Integer>();

        Map<String, Integer> qaLeads = new Map<String, Integer>();
        Map<String, Integer> qaSigned = new Map<String, Integer>();

        Map<Id, RepAcc> repMap = new Map<Id, RepAcc>();

        for (Intake__c intake : intakes) {

            Boolean signed =
                intake.Status__c != null &&
                SIGNED_STATUSES.contains(intake.Status__c);

            Task firstCall = firstCallMap.get(intake.Id);

            // skill axis value comes from the first substantive call's Task
            Decimal qa = (firstCall != null) ? firstCall.Call_QA_Score__c : null;

            Decimal mins = null;

            if (firstCall != null) {

                mins =
                    (firstCall.CreatedDate.getTime()
                    - intake.CreatedDate.getTime())
                    / 60000.0;

                if (mins < 0) {
                    mins = null;
                }
            }

            // Speed Buckets
            if (mins != null) {

                String speedBucket = speedBand(mins);

                bump(spLeads, speedBucket);

                if (signed) {
                    bump(spSigned, speedBucket);
                }
            }

            // QA (skill) Buckets
            if (qa != null) {

                String qaBucket = qaBand(qa);

                bump(qaLeads, qaBucket);

                if (signed) {
                    bump(qaSigned, qaBucket);
                }
            }

            // Rep Matrix using the first-substantive-call owner
            if (firstCall != null &&
                firstCall.OwnerId != null &&
                String.valueOf(firstCall.OwnerId).startsWith('005')) {

                RepAcc acc = repMap.get(firstCall.OwnerId);

                if (acc == null) {

                    acc = new RepAcc();
                    acc.name = firstCall.Owner != null
                        ? firstCall.Owner.Name
                        : 'Specialist';

                    repMap.put(firstCall.OwnerId, acc);
                }

                acc.leads++;

                if (signed) {
                    acc.signed++;
                }

                if (mins != null) {
                    acc.sumMins += mins;
                    acc.cntMins++;
                }

                if (qa != null) {
                    acc.sumQa += qa;
                    acc.cntQa++;
                }
            }
        }

        DashboardData result = new DashboardData();

        result.speedBuckets =
            buildBuckets(
                SPEED_ORDER,
                spLeads,
                spSigned
            );

        result.qaBuckets =
            buildBuckets(
                QA_ORDER,
                qaLeads,
                qaSigned
            );

        result.reps =
            buildReps(
                repMap
            );

        return result;
    }

    private static final List<String> SPEED_ORDER = new List<String>{
        'Under 5 min',
        '5–15 min',
        '15–60 min',
        'Over 60 min'
    };

    private static final List<String> QA_ORDER = new List<String>{
        'Excellent (80–100)',
        'Good (65–79)',
        'Fair (50–64)',
        'Poor (under 50)'
    };

    private static String speedBand(Decimal mins) {

        if (mins < 5) {
            return 'Under 5 min';
        }

        if (mins < 15) {
            return '5–15 min';
        }

        if (mins < 60) {
            return '15–60 min';
        }

        return 'Over 60 min';
    }

    private static String qaBand(Decimal qa) {

        if (qa >= 80) {
            return 'Excellent (80–100)';
        }

        if (qa >= 65) {
            return 'Good (65–79)';
        }

        if (qa >= 50) {
            return 'Fair (50–64)';
        }

        return 'Poor (under 50)';
    }

    private static void bump(
        Map<String, Integer> mapData,
        String key
    ) {
        mapData.put(
            key,
            (mapData.containsKey(key)
                ? mapData.get(key)
                : 0) + 1
        );
    }

    private static List<Bucket> buildBuckets(
        List<String> order,
        Map<String, Integer> leads,
        Map<String, Integer> signed
    ) {

        List<Bucket> buckets = new List<Bucket>();

        for (String label : order) {

            Integer leadCount =
                leads.containsKey(label)
                ? leads.get(label)
                : 0;

            if (leadCount == 0) {
                continue;
            }

            Integer signedCount =
                signed.containsKey(label)
                ? signed.get(label)
                : 0;

            Bucket bucket = new Bucket();
            bucket.label = label;
            bucket.leads = leadCount;
            bucket.conv = pct(
                signedCount,
                leadCount
            );

            buckets.add(bucket);
        }

        return buckets;
    }

    private static List<Rep> buildReps(
        Map<Id, RepAcc> repMap
    ) {

        List<Rep> reps = new List<Rep>();

        for (RepAcc acc : repMap.values()) {

            if (acc.cntMins == 0 ||
                acc.cntQa == 0) {
                continue;
            }

            Rep rep = new Rep();

            rep.name = acc.name;

            rep.responseMins =
                (acc.sumMins / acc.cntMins)
                .setScale(1);

            rep.qaScore =
                (acc.sumQa / acc.cntQa)
                .setScale(0);

            rep.conversion =
                pct(acc.signed, acc.leads);

            rep.leads = acc.leads;

            reps.add(rep);
        }

        reps.sort();

        if (reps.size() > MAX_REPS) {

            List<Rep> top = new List<Rep>();

            for (Integer i = 0; i < MAX_REPS; i++) {
                top.add(reps[i]);
            }

            reps = top;
        }

        return reps;
    }

    private static Decimal pct(
        Integer part,
        Integer whole
    ) {
        return whole == 0
            ? 0
            : (
                Decimal.valueOf(part) * 100 / whole
              ).setScale(0);
    }

    public class DashboardData {
        @AuraEnabled public List<Bucket> speedBuckets;
        @AuraEnabled public List<Bucket> qaBuckets;
        @AuraEnabled public List<Rep> reps;
    }

    public class Bucket {
        @AuraEnabled public String label;
        @AuraEnabled public Decimal conv;
        @AuraEnabled public Integer leads;
    }

    public class Rep implements Comparable {

        @AuraEnabled public String name;
        @AuraEnabled public Decimal responseMins;
        @AuraEnabled public Decimal qaScore;
        @AuraEnabled public Decimal conversion;
        @AuraEnabled public Integer leads;

        public Integer compareTo(Object obj) {
            return ((Rep)obj).leads - this.leads;
        }
    }

    private class RepAcc {
        String name;
        Decimal sumMins = 0;
        Integer cntMins = 0;
        Decimal sumQa = 0;
        Integer cntQa = 0;
        Integer leads = 0;
        Integer signed = 0;
    }
}