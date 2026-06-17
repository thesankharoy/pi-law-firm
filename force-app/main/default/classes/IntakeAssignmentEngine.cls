public class IntakeAssignmentEngine {
    // Single source of truth for closed statuses — used in both live count
    // queries and the drain query so they're always consistent.
    @TestVisible
    static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Converted', 'Turned Down', 'Referred Out' };

    // ── Called from IntakeTrigger — before insert ─────────────────
    public static void assignIntakes(List<Intake__c> intakes) {
        if (intakes == null || intakes.isEmpty())
            return;

        List<Intake_Assignment_Rule__mdt> rules = loadRules();
        Map<String, List<Intake_Assignment_Condition__mdt>> condMap = loadConditions();

        // Pass 1: evaluate rules, set direct user assignments,
        //         bucket queue-bound intakes for bulk round-robin
        Map<Id, List<Intake__c>> queueBound = new Map<Id, List<Intake__c>>();
        for (Intake__c intake : intakes) {
            Id targetId = evaluateRules(intake, rules, condMap);
            if (targetId == null)
                continue; // no matching rule — leave for manual handling

            intake.OwnerId = targetId;

            if (isQueue(targetId)) {
                if (!queueBound.containsKey(targetId))
                    queueBound.put(targetId, new List<Intake__c>());
                queueBound.get(targetId).add(intake);
            }
            // else: rule points directly at a user — OwnerId already set
        }

        // Pass 2: bulk round-robin for all queue-bound intakes
        if (!queueBound.isEmpty())
            assignSpecialists(queueBound);
        // No DML here — before insert modifies Trigger.new in place
    }

    // ── Bulk round-robin ─────────────────────────────────────────
    // Constant SOQL/DML cost regardless of batch size:
    //   1 GroupMember query (all queues at once)
    //   1 aggregate Intake query (live counts for all candidates)
    //   1 Intake_Specialist__c query (all candidates at once)
    //   1 update DML (only specialists that received at least one intake)
    private static void assignSpecialists(Map<Id, List<Intake__c>> queueBound) {
        Set<Id> queueIds = queueBound.keySet();

        // Query 1: find every active specialist who is a member of any relevant queue
        Map<Id, Set<Id>> queueToUserIds = new Map<Id, Set<Id>>();
        Set<Id> allUserIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT GroupId, UserOrGroupId
            FROM GroupMember
            WHERE
                GroupId IN :queueIds
                AND UserOrGroupId IN (SELECT User__c FROM Intake_Specialist__c WHERE Active__c = TRUE)
        ]) {
            if (!queueToUserIds.containsKey(gm.GroupId))
                queueToUserIds.put(gm.GroupId, new Set<Id>());
            queueToUserIds.get(gm.GroupId).add(gm.UserOrGroupId);
            allUserIds.add(gm.UserOrGroupId);
        }
        if (allUserIds.isEmpty())
            return;

        // Query 2: live open-intake count per candidate user
        // One aggregate query — never reads the stored Current_Active_Count__c for logic
        Map<Id, Integer> liveCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT OwnerId oid, COUNT(Id) cnt
            FROM Intake__c
            WHERE OwnerId IN :allUserIds AND Status__c NOT IN :CLOSED_STATUSES
            GROUP BY OwnerId
        ]) {
            liveCounts.put((Id) ar.get('oid'), (Integer) ar.get('cnt'));
        }

        // Query 3: load specialist records for rotation metadata
        // Has_Capacity__c and Active__c are formula fields — valid in WHERE on sObject
        Map<Id, Candidate> candidateByUser = new Map<Id, Candidate>();
        for (Intake_Specialist__c s : [
            SELECT Id, User__c, Last_Assigned__c, Max_Capacity__c
            FROM Intake_Specialist__c
            WHERE User__c IN :allUserIds AND Active__c = TRUE AND Has_Capacity__c = TRUE
        ]) {
            Integer liveCount = liveCounts.containsKey(s.User__c) ? liveCounts.get(s.User__c) : 0;
            Candidate c = new Candidate(s, liveCount);
            if (c.remaining > 0)
                candidateByUser.put(s.User__c, c);
        }
        if (candidateByUser.isEmpty())
            return;

        DateTime nowTs = System.now();
        Long baseMillis = nowTs.getTime();
        Integer pickSeq = 0;
        Map<Id, Intake_Specialist__c> touched = new Map<Id, Intake_Specialist__c>();

        for (Id queueId : queueBound.keySet()) {
            Set<Id> userIds = queueToUserIds.get(queueId);
            if (userIds == null || userIds.isEmpty())
                continue;

            // Candidate objects are shared across queues — so if a specialist
            // belongs to two queues their remaining capacity decrements correctly
            List<Candidate> pool = new List<Candidate>();
            for (Id uid : userIds) {
                Candidate c = candidateByUser.get(uid);
                if (c != null)
                    pool.add(c);
            }
            if (pool.isEmpty())
                continue;

            for (Intake__c intake : queueBound.get(queueId)) {
                Candidate best = pickBest(pool);
                if (best == null)
                    break; // everyone at capacity — leave remaining on queue

                intake.OwnerId = best.spec.User__c;
                best.remaining -= 1;
                best.liveCount += 1; // track in-transaction assignments
                best.sortKey = baseMillis + (++pickSeq); // rotate to back
                best.spec.Last_Assigned__c = nowTs;
                // Refresh stored count = live snapshot + how many we've assigned
                // in this transaction so the widget always shows a fresh number
                best.spec.Current_Active_Count__c = best.liveCount;
                touched.put(best.spec.Id, best.spec);
            }
        }

        if (!touched.isEmpty())
            update touched.values(); // single DML, deduped by Id
    }

    // Least-recently-assigned with live count as tiebreaker
    private static Candidate pickBest(List<Candidate> pool) {
        Candidate best = null;
        for (Candidate c : pool) {
            if (c.remaining <= 0)
                continue;
            if (
                best == null ||
                c.sortKey < best.sortKey ||
                (c.sortKey == best.sortKey &&
                c.liveCount < best.liveCount)
            ) {
                best = c;
            }
        }
        return best;
    }

    // In-memory view of a specialist for round-robin rotation within one transaction
    private class Candidate {
        Intake_Specialist__c spec;
        Long sortKey; // smaller = assigned longer ago; 0 = never assigned
        Integer liveCount; // current open intakes from DB + assigned this transaction
        Integer remaining; // capacity left in this transaction

        Candidate(Intake_Specialist__c s, Integer liveCount) {
            this.spec = s;
            this.liveCount = liveCount;
            Integer maxCap = (s.Max_Capacity__c == null) ? 15 : (Integer) s.Max_Capacity__c;
            this.remaining = Math.max(0, maxCap - liveCount);
            this.sortKey = (s.Last_Assigned__c == null) ? 0L : s.Last_Assigned__c.getTime();
        }
    }

    // ── Drain queue backlog when a specialist goes Active ─────────
    public static void drainQueueForSpecialist(Id userId) {
        Set<Id> queueIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT GroupId
            FROM GroupMember
            WHERE UserOrGroupId = :userId AND Group.Type = 'Queue'
        ])
            queueIds.add(gm.GroupId);

        if (queueIds.isEmpty())
            return;

        List<Intake_Specialist__c> specs = [
            SELECT Id, Max_Capacity__c
            FROM Intake_Specialist__c
            WHERE User__c = :userId AND Active__c = TRUE
            LIMIT 1
        ];
        if (specs.isEmpty())
            return;

        // Live count — never trust the stored field for capacity logic
        Integer liveCount = [
            SELECT COUNT()
            FROM Intake__c
            WHERE OwnerId = :userId AND Status__c NOT IN :CLOSED_STATUSES
        ];
        Integer cap = specs[0].Max_Capacity__c != null ? (Integer) specs[0].Max_Capacity__c : 15;
        Integer available = cap - liveCount;
        if (available <= 0)
            return;

        List<Intake__c> queued = [
            SELECT Id, OwnerId
            FROM Intake__c
            WHERE OwnerId IN :queueIds AND Status__c NOT IN :CLOSED_STATUSES
            ORDER BY CreatedDate ASC
            LIMIT :available
        ];
        if (queued.isEmpty())
            return;

        for (Intake__c i : queued)
            i.OwnerId = userId;

        // Refresh stored count = live snapshot + how many we just drained
        specs[0].Last_Assigned__c = System.now();
        specs[0].Current_Active_Count__c = liveCount + queued.size();
        update queued;
        update specs[0];
    }

    // ── Rule Evaluation ───────────────────────────────────────────
    private static Id evaluateRules(
        Intake__c intake,
        List<Intake_Assignment_Rule__mdt> rules,
        Map<String, List<Intake_Assignment_Condition__mdt>> condMap
    ) {
        for (Intake_Assignment_Rule__mdt rule : rules) {
            List<Intake_Assignment_Condition__mdt> conditions = condMap.containsKey(rule.DeveloperName)
                ? condMap.get(rule.DeveloperName)
                : new List<Intake_Assignment_Condition__mdt>();

            if (conditions.isEmpty())
                continue;

            if (evaluateConditionGroup(intake, conditions, rule.Condition_Logic__c)) {
                return Id.valueOf(rule.Assign_To_Id__c);
            }
        }
        return null;
    }

    private static Boolean evaluateConditionGroup(
        Intake__c intake,
        List<Intake_Assignment_Condition__mdt> conditions,
        String logic
    ) {
        Boolean isAnd = (logic == null || logic.equalsIgnoreCase('AND'));
        for (Intake_Assignment_Condition__mdt cond : conditions) {
            Boolean result = evaluateSingle(intake, cond);
            if (isAnd && !result)
                return false;
            if (!isAnd && result)
                return true;
        }
        return isAnd;
    }

    private static Boolean evaluateSingle(Intake__c intake, Intake_Assignment_Condition__mdt cond) {
        String rawValue = getFieldValue(intake, cond.Field_API_Name__c);
        String condValue = cond.Value__c;
        String op = cond.Operator__c;

        if (op == 'is_blank')
            return String.isBlank(rawValue);
        if (op == 'is_not_blank')
            return String.isNotBlank(rawValue);
        if (rawValue == null)
            return false;

        String fv = rawValue.toLowerCase();
        String cv = condValue == null ? '' : condValue.toLowerCase();

        switch on op {
            when 'equals' {
                return fv == cv;
            }
            when 'not_equals' {
                return fv != cv;
            }
            when 'contains' {
                return fv.contains(cv);
            }
            when 'starts_with' {
                return fv.startsWith(cv);
            }
            when 'ends_with' {
                return fv.endsWith(cv);
            }
            when 'greater_than' {
                try {
                    return Decimal.valueOf(rawValue) > Decimal.valueOf(condValue);
                } catch (Exception e) {
                    return false;
                }
            }
            when 'less_than' {
                try {
                    return Decimal.valueOf(rawValue) < Decimal.valueOf(condValue);
                } catch (Exception e) {
                    return false;
                }
            }
            when else {
                return false;
            }
        }
    }

    private static String getFieldValue(Intake__c intake, String fieldApiName) {
        try {
            Object val = intake.get(fieldApiName);
            return val == null ? null : String.valueOf(val);
        } catch (Exception e) {
            return null;
        }
    }

    // ── Deprecated: single-record round-robin ─────────────────────
    // Kept only so existing @TestVisible unit tests still compile.
    // The trigger path now uses assignSpecialists() via assignIntakes().
    // Safe to delete once tests are migrated to assignIntakes().
    @TestVisible
    private static Id findNextSpecialist(Id queueId) {
        Set<Id> queueUserIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT UserOrGroupId
            FROM GroupMember
            WHERE
                GroupId = :queueId
                AND UserOrGroupId IN (SELECT User__c FROM Intake_Specialist__c WHERE Active__c = TRUE)
        ])
            queueUserIds.add(gm.UserOrGroupId);

        if (queueUserIds.isEmpty())
            return null;

        // Live count for candidate users
        Map<Id, Integer> liveCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT OwnerId oid, COUNT(Id) cnt
            FROM Intake__c
            WHERE OwnerId IN :queueUserIds AND Status__c NOT IN :CLOSED_STATUSES
            GROUP BY OwnerId
        ])
            liveCounts.put((Id) ar.get('oid'), (Integer) ar.get('cnt'));

        List<Intake_Specialist__c> candidates = [
            SELECT Id, User__c, Last_Assigned__c, Max_Capacity__c
            FROM Intake_Specialist__c
            WHERE User__c IN :queueUserIds AND Active__c = TRUE AND Has_Capacity__c = TRUE
            ORDER BY Last_Assigned__c ASC NULLS FIRST
            LIMIT 1
        ];
        if (candidates.isEmpty())
            return null;

        Integer liveCount = liveCounts.containsKey(candidates[0].User__c) ? liveCounts.get(candidates[0].User__c) : 0;

        candidates[0].Last_Assigned__c = System.now();
        candidates[0].Current_Active_Count__c = liveCount + 1;
        update candidates[0];

        return candidates[0].User__c;
    }

    // ── ID type check ─────────────────────────────────────────────
    private static Boolean isQueue(Id recordId) {
        return String.valueOf(recordId).startsWith('00G');
    }

    // ── CMT Loaders ───────────────────────────────────────────────
    private static List<Intake_Assignment_Rule__mdt> loadRules() {
        return [
            SELECT
                DeveloperName,
                MasterLabel,
                Order__c,
                Active__c,
                Assign_To_Type__c,
                Assign_To_Id__c,
                Assign_To_Name__c,
                Condition_Logic__c,
                Stop_On_Match__c
            FROM Intake_Assignment_Rule__mdt
            WHERE Active__c = TRUE
            ORDER BY Order__c ASC
        ];
    }

    private static Map<String, List<Intake_Assignment_Condition__mdt>> loadConditions() {
        Map<String, List<Intake_Assignment_Condition__mdt>> result = new Map<String, List<Intake_Assignment_Condition__mdt>>();
        // ORDER BY local field only — ORDER BY on CMT relationship fields
        // (Rule__r.Order__c) throws "operation not yet supported by this sObject
        // storage type". Rule order is already correct because loadRules() is sorted.
        for (Intake_Assignment_Condition__mdt c : [
            SELECT DeveloperName, Rule__r.DeveloperName, Field_API_Name__c, Operator__c, Value__c, Order__c
            FROM Intake_Assignment_Condition__mdt
            ORDER BY Order__c ASC
        ]) {
            String key = c.Rule__r.DeveloperName;
            if (!result.containsKey(key))
                result.put(key, new List<Intake_Assignment_Condition__mdt>());
            result.get(key).add(c);
        }
        return result;
    }
}
