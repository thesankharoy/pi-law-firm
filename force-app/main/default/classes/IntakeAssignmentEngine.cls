public class IntakeAssignmentEngine {
    // Called from IntakeTrigger — before insert, OwnerId set directly on Trigger.new
    public static void assignIntakes(List<Intake__c> intakes) {
        if (intakes == null || intakes.isEmpty())
            return;

        // Load all rules + conditions once
        List<Intake_Assignment_Rule__mdt> rules = loadRules();
        Map<String, List<Intake_Assignment_Condition__mdt>> condMap = loadConditions();

        for (Intake__c intake : intakes) {
            Id targetId = evaluateRules(intake, rules, condMap);
            if (targetId == null) {
                continue; // No matching rule — leave unassigned for manual handling
            }

            if (targetId != null) {
                intake.OwnerId = targetId;

                // If target is a queue, try to find active specialist now
                if (isQueue(targetId)) {
                    Id specialistUserId = findNextSpecialist(targetId);
                    if (specialistUserId != null) {
                        intake.OwnerId = specialistUserId;
                    }
                } else {
                    // Rule assigned directly to a user
                    intake.OwnerId = targetId;
                }
            }
        }
        // No DML — before insert modifies Trigger.new in place
    }

    // ── Called when specialist goes Active — drain their queues ──
    public static void drainQueueForSpecialist(Id userId) {
        // Get all queues this user is a member of
        Set<Id> queueIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT GroupId
            FROM GroupMember
            WHERE UserOrGroupId = :userId AND Group.Type = 'Queue'
        ]) {
            queueIds.add(gm.GroupId);
        }

        if (queueIds.isEmpty())
            return;

        // Check capacity
        List<Intake_Specialist__c> specs = [
            SELECT Id, Current_Active_Count__c, Max_Capacity__c
            FROM Intake_Specialist__c
            WHERE User__c = :userId AND Active__c = TRUE
            LIMIT 1
        ];
        if (specs.isEmpty())
            return;

        Integer available = (Integer) (specs[0].Max_Capacity__c - specs[0].Current_Active_Count__c);
        if (available <= 0)
            return;

        // Get oldest unassigned intakes sitting in this specialist's queues
        List<Intake__c> queued = [
            SELECT Id, OwnerId
            FROM Intake__c
            WHERE OwnerId IN :queueIds AND Status__c NOT IN ('Converted', 'Turned Down', 'Referred Out')
            ORDER BY CreatedDate ASC
            LIMIT :available
        ];
        if (queued.isEmpty())
            return;

        for (Intake__c i : queued)
            i.OwnerId = userId;

        specs[0].Last_Assigned__c = System.now();
        update queued;
        update specs[0];
    }

    // ── Rule Evaluation ──────────────────────────────────────────
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

            Boolean matched = evaluateConditionGroup(intake, conditions, rule.Condition_Logic__c);

            if (matched) {
                return Id.valueOf(rule.Assign_To_Id__c);
                // Stop_On_Match__c is implicitly true here (return on first match)
                // For OR-chain rules without stop, remove the return and collect all targets
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
                return false; // AND: one false = group false
            if (!isAnd && result)
                return true; // OR: one true = group true
        }

        return isAnd; // AND all passed = true; OR none matched = false
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

    // ── Dynamic field read from SObject ─────────────────────────
    private static String getFieldValue(Intake__c intake, String fieldApiName) {
        try {
            Object val = intake.get(fieldApiName);
            return val == null ? null : String.valueOf(val);
        } catch (Exception e) {
            return null;
        }
    }

    // ── Round-Robin Specialist Finder ────────────────────────────
    @TestVisible
    private static Id findNextSpecialist(Id queueId) {
        // Get all user IDs who are queue members AND have an Intake_Specialist__c record
        Set<Id> queueUserIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT UserOrGroupId
            FROM GroupMember
            WHERE
                GroupId = :queueId
                AND UserOrGroupId IN (SELECT User__c FROM Intake_Specialist__c WHERE Active__c = TRUE)
        ]) {
            queueUserIds.add(gm.UserOrGroupId);
        }

        if (queueUserIds.isEmpty())
            return null;

        // Lock the best candidate — FOR UPDATE prevents race conditions
        List<Intake_Specialist__c> candidates = [
            SELECT Id, User__c, Last_Assigned__c, Current_Active_Count__c, Max_Capacity__c
            FROM Intake_Specialist__c
            WHERE User__c IN :queueUserIds AND Active__c = TRUE AND Has_Capacity__c = TRUE
            ORDER BY Last_Assigned__c ASC NULLS FIRST, Current_Active_Count__c ASC
            LIMIT 1
        ];

        if (candidates.isEmpty())
            return null;

        candidates[0].Last_Assigned__c = System.now();
        update candidates[0];

        return candidates[0].User__c;
    }

    // ── ID type check ────────────────────────────────────────────
    private static Boolean isQueue(Id recordId) {
        return String.valueOf(recordId).startsWith('00G');
    }

    // ── CMT Loaders ──────────────────────────────────────────────
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
