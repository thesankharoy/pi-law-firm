public with sharing class UserAvailabilityService {
    // ── Get current user's specialist record (auto-creates if missing) ──
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getMyStatus() {
        Id userId = UserInfo.getUserId();
        User u = [SELECT Id, SmallPhotoUrl FROM User WHERE Id = :userId LIMIT 1];

        List<Intake_Specialist__c> specs = [
            SELECT Id, Status__c, Active__c, Max_Capacity__c, Last_Assigned__c, Last_Heartbeat__c
            FROM Intake_Specialist__c
            WHERE User__c = :userId
            LIMIT 1
        ];

        Intake_Specialist__c spec;
        if (specs.isEmpty()) {
            spec = new Intake_Specialist__c(User__c = userId, Status__c = 'Inactive', Max_Capacity__c = 15);
            insert spec;
        } else {
            spec = specs[0];
        }

        // Live count — never read Current_Active_Count__c for display;
        // the engine writes that field; we always derive it fresh here
        Integer liveActiveCount = [
            SELECT COUNT()
            FROM Intake__c
            WHERE OwnerId = :userId AND Status__c NOT IN ('Converted', 'Turned Down', 'Referred Out')
        ];

        Integer assignedToday = [
            SELECT COUNT()
            FROM Intake__c
            WHERE OwnerId = :userId AND CreatedDate = TODAY
        ];

        return new Map<String, Object>{
            'id' => spec.Id,
            'status' => spec.Status__c,
            'isActive' => spec.Active__c,
            'activeCount' => liveActiveCount,
            'maxCapacity' => spec.Max_Capacity__c != null ? (Integer) spec.Max_Capacity__c : 15,
            'assignedToday' => assignedToday,
            'userName' => UserInfo.getName(),
            'photoUrl' => u.SmallPhotoUrl
        };
    }

    // ── Get open intakes assigned to current user ──
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getOpenIntakes() {
        Id userId = UserInfo.getUserId();

        List<Map<String, Object>> result = new List<Map<String, Object>>();

        for (Intake__c i : [
            SELECT
                Id,
                Name,
                Status__c,
                Incident_Type__c,
                CreatedDate,
                Priority__c,
                Priority_Rank__c,
                Is_At_Risk__c,
                Risk_Reason__c,
                Client__r.Name
            FROM Intake__c
            WHERE OwnerId = :userId AND Status__c NOT IN ('Converted', 'Referred Out', 'Turned Down')
            ORDER BY CreatedDate DESC
            LIMIT 50
        ]) {
            result.add(
                new Map<String, Object>{
                    'id' => i.Id,
                    'name' => i.Name,
                    'status' => i.Status__c,
                    'incidentType' => i.Incident_Type__c,
                    'clientName' => (i.Client__r != null && i.Client__r.Name != null) ? i.Client__r.Name : '—',
                    'createdDate' => i.CreatedDate,
                    'priority' => i.Priority__c,
                    'priorityRank' => i.Priority_Rank__c,
                    'isAtRisk' => i.Is_At_Risk__c,
                    'riskReason' => i.Risk_Reason__c
                }
            );
        }
        return result;
    }

    // ── Toggle status ────────────────────────────────────────────
    @AuraEnabled
    public static Map<String, Object> setStatus(String newStatus) {
        Id userId = UserInfo.getUserId();

        // Validate allowed values
        Set<String> allowed = new Set<String>{ 'Active', 'Inactive', 'On Break' };
        if (!allowed.contains(newStatus)) {
            throw new AuraHandledException('Invalid status: ' + newStatus);
        }

        List<Intake_Specialist__c> specs = [
            SELECT Id, Status__c, Current_Active_Count__c, Max_Capacity__c
            FROM Intake_Specialist__c
            WHERE User__c = :userId
            LIMIT 1
        ];

        Intake_Specialist__c spec;
        if (specs.isEmpty()) {
            spec = new Intake_Specialist__c(
                User__c = userId,
                Status__c = newStatus,
                Max_Capacity__c = 15,
                Last_Heartbeat__c = System.now()
            );
            insert spec;
        } else {
            spec = specs[0];
            spec.Status__c = newStatus;
            spec.Last_Heartbeat__c = System.now();
            update spec;
        }

        // If going Active, drain queues in a future context (avoids mixed DML / governor issues)
        if (newStatus == 'Active') {
            drainQueuesAsync(userId);
        }

        return getMyStatus();
    }

    // ── Heartbeat — called every 3 minutes by LWC ────────────────
    @AuraEnabled
    public static void heartbeat() {
        Id userId = UserInfo.getUserId();
        List<Intake_Specialist__c> specs = [
            SELECT Id
            FROM Intake_Specialist__c
            WHERE User__c = :userId AND Active__c = TRUE
            LIMIT 1
        ];
        if (!specs.isEmpty()) {
            specs[0].Last_Heartbeat__c = System.now();
            update specs[0];
        }
    }

    @AuraEnabled
    public static void triggerPriorityRanking() {
        // Callout — no DML before this
        LeadPriorityService.rankIntakes(UserInfo.getUserId());
    }

    @AuraEnabled
    public static void forceRefreshPriorityRanking() {
        LeadPriorityService.forceRankIntakes(UserInfo.getUserId());
    }

    @AuraEnabled(cacheable=false)
    public static Boolean isPriorityRankingFresh() {
        return LeadPriorityService.isCacheFresh(UserInfo.getUserId());
    }

    // ── Scheduled cleanup — marks stale specialists as Inactive ──
    public static void expireStaleSpecialists() {
        DateTime cutoff = System.now().addMinutes(-5);
        List<Intake_Specialist__c> stale = [
            SELECT Id, Status__c, User__r.Name
            FROM Intake_Specialist__c
            WHERE Active__c = TRUE AND Last_Heartbeat__c < :cutoff
        ];

        if (stale.isEmpty())
            return;

        for (Intake_Specialist__c s : stale) {
            s.Status__c = 'Inactive';
        }
        update stale;

        // Optionally notify manager — add notification logic here
    }

    @future
    private static void drainQueuesAsync(Id userId) {
        IntakeAssignmentEngine.drainQueueForSpecialist(userId);
    }
}
