public class IntakeLifecycleService {
    // Rank defines legal direction — can only move forward (higher number)
    private static final Map<String, Integer> RT_RANK = new Map<String, Integer>{
        'New_Intake' => 1,
        'Active_Intake' => 2,
        'Converted_Intake' => 3
    };

    // ── BEFORE INSERT: called after IntakeAssignmentEngine.assignIntakes ─────
    // Active_Intake / Converted_Intake created directly from UI never reach here.
    // OwnerId is already stamped by the engine so we read the final value here.
    public static void setInitialState(List<Intake__c> intakes) {
        Id activeIntakeRtId = recordTypeId('Active_Intake');

        for (Intake__c i : intakes) {
            // Null owner or queue owner → New_Intake / New (unassigned, waiting in queue)
            // Real user owner           → Active_Intake / Assigned (specialist has it)
            Boolean ownedByUser = i.OwnerId != null && i.OwnerId.getSObjectType() == Schema.User.SObjectType;

            if (ownedByUser) {
                // Assignment rule pointed directly at a user — skip the queue,
                // promote straight to Active_Intake + Assigned.
                i.RecordTypeId = activeIntakeRtId;
                i.Status__c = 'Assigned';
            }
        }
    }

    // ── BEFORE UPDATE: enforce rules + handle transitions ────────────────────
    public static void manageLifecycle(List<Intake__c> newList, Map<Id, Intake__c> oldMap) {
        Id newIntakeRtId = recordTypeId('New_Intake');
        Id activeIntakeRtId = recordTypeId('Active_Intake');
        Id convertedIntakeRtId = recordTypeId('Converted_Intake');

        // Reverse map so we can look up developer name from Id for rank checks
        Map<Id, String> rtIdToDevName = new Map<Id, String>{
            newIntakeRtId => 'New_Intake',
            activeIntakeRtId => 'Active_Intake',
            convertedIntakeRtId => 'Converted_Intake'
        };

        for (Intake__c i : newList) {
            Intake__c old = oldMap.get(i.Id);

            // ── 1. Block backward RT movement (user/admin attempt) ──────────
            String oldRtDev = rtIdToDevName.get(old.RecordTypeId);
            String newRtDev = rtIdToDevName.get(i.RecordTypeId);

            if (oldRtDev != null && newRtDev != null) {
                Integer oldRank = RT_RANK.get(oldRtDev);
                Integer newRank = RT_RANK.get(newRtDev);
                if (newRank != null && newRank < oldRank) {
                    i.RecordTypeId.addError(
                        'Intake lifecycle cannot go backward. ' +
                            oldRtDev.replace('_', ' ') +
                            ' cannot be changed to ' +
                            newRtDev.replace('_', ' ') +
                            '.'
                    );
                    continue; // skip further processing for this record
                }
            }

            // ── 2. Queue → User transition: promote to Active_Intake ────────
            if (
                i.OwnerId != old.OwnerId &&
                i.OwnerId != null &&
                i.OwnerId.getSObjectType() == Schema.User.SObjectType
            ) {
                Boolean wasQueue = old.OwnerId == null || old.OwnerId.getSObjectType() != Schema.User.SObjectType;

                // Only promote — never demote. New_Intake → Active_Intake only.
                if (wasQueue && i.RecordTypeId == newIntakeRtId) {
                    i.RecordTypeId = activeIntakeRtId;
                    i.Status__c = 'Assigned';
                }
            }

            // ── 3. Status = Converted → promote to Converted_Intake ─────────
            if (i.Status__c == 'Converted' && old.Status__c != 'Converted' && i.RecordTypeId != convertedIntakeRtId) {
                if (i.RecordTypeId == activeIntakeRtId) {
                    i.RecordTypeId = convertedIntakeRtId;
                } else {
                    // Intake must be Active before it can be Converted
                    i.Status__c.addError('An Intake must be in the Active Intake stage before it can be Converted.');
                }
            }

            // ── 4. Stamp the retainer clock for the revenue-leak detector ───
            // First time Status becomes "Retainer Agreement Sent", record when —
            // this is the leak clock RevenueLeakDetector measures the SLA against.
            if (i.Status__c == 'Retainer Agreement Sent'
                && old.Status__c != 'Retainer Agreement Sent'
                && i.Retainer_Sent_At__c == null) {
                i.Retainer_Sent_At__c = Datetime.now();
            }
        }
    }

    // ── Record type Id cache ─────────────────────────────────────────────────
    private static Map<String, Id> rtCache = new Map<String, Id>();
    private static Id recordTypeId(String devName) {
        if (rtCache.containsKey(devName))
            return rtCache.get(devName);
        Id rid = Schema.SObjectType.Intake__c.getRecordTypeInfosByDeveloperName().get(devName).getRecordTypeId();
        rtCache.put(devName, rid);
        return rid;
    }
}