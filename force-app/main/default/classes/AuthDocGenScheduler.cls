/**
 * AuthDocGenScheduler  (self-healing, self-perpetuating)
 *
 * PERMANENCE DESIGN — three things make this not break again:
 *  1. SELF-RESCHEDULE: at the end of every run it schedules its own next run,
 *     so the cron entry can never silently disappear. Start it ONCE; it keeps
 *     itself alive forever after.
 *  2. STATE-BASED PICKUP: it finds work two ways — the Auth_Docs_Pending__c flag
 *     AND any signed intake missing its 3 docs. So even if a flag write is ever
 *     missed, the missing documents themselves are the signal — nothing strands.
 *  3. IDEMPOTENT: GenerateIntakeAuthDocsQueueable skips intakes that already have
 *     all 3 docs, so re-runs never create duplicates.
 *
 * START IT ONCE (as a licensed admin):
 *   AuthDocGenScheduler.start();
 * That's the only manual action ever needed.
 */
public without sharing class AuthDocGenScheduler implements Schedulable {

    private static final Integer BATCH_LIMIT   = 40;
    private static final Integer RERUN_SECONDS = 120;   // next run 2 min later
    private static final String  JOB_PREFIX    = 'AuthDocGen SelfHeal';
    private static final String  STATUS_SIGNED = 'Retainer Agreement Signed';
    private static final Set<String> DOC_TYPES = new Set<String>{
        'Retainer Agreement', 'Letter of Representation', 'HIPAA Authorization'
    };

    /** Call ONCE to start the perpetual chain. */
    public static void start() {
        // Clear any old instances first so we don't stack duplicates.
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'AuthDocGen%']) {
            try { System.abortJob(ct.Id); } catch (Exception e) {}
        }
        scheduleNext();
    }

    public void execute(SchedulableContext sc) {
        try {
            processPending();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[AuthDocGenScheduler] run error: ' + e.getMessage());
        }
        // Always chain the next run, even if this one hit an error.
        scheduleNext();
    }

    private void processPending() {
        Set<Id> targetIds = new Set<Id>();

        // (a) flagged intakes
        for (Intake__c i : [SELECT Id FROM Intake__c WHERE Auth_Docs_Pending__c = true AND Status__c = :STATUS_SIGNED LIMIT :BATCH_LIMIT]) {
            targetIds.add(i.Id);
        }

        // (b) safety net: signed intakes missing any of their 3 docs
        Map<Id, Integer> docCount = new Map<Id, Integer>();
        for (Intake__c i : [SELECT Id FROM Intake__c WHERE Status__c = :STATUS_SIGNED
                            ORDER BY LastModifiedDate DESC LIMIT :BATCH_LIMIT]) {
            docCount.put(i.Id, 0);
        }
        if (!docCount.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Intake__c iid, COUNT(Id) c
                FROM Document__c
                WHERE Intake__c IN :docCount.keySet()
                  AND Document_Type__c IN :DOC_TYPES
                GROUP BY Intake__c
            ]) {
                docCount.put((Id) ar.get('iid'), (Integer) ar.get('c'));
            }
            for (Id iid : docCount.keySet()) {
                if (docCount.get(iid) < 3) targetIds.add(iid);
            }
        }

        if (targetIds.isEmpty()) {
            System.debug(LoggingLevel.INFO, '[AuthDocGenScheduler] Nothing to do.');
            return;
        }

        // Clear flags for the ones that had it (queueable re-confirms + is idempotent).
        List<Intake__c> toClear = new List<Intake__c>();
        for (Id iid : targetIds) toClear.add(new Intake__c(Id = iid, Auth_Docs_Pending__c = false));
        update toClear;

        for (Id iid : targetIds) {
            System.enqueueJob(new GenerateIntakeAuthDocsQueueable(iid));
            System.debug(LoggingLevel.INFO, '[AuthDocGenScheduler] Enqueued ' + iid
                + ' as ' + UserInfo.getUserName());
        }
    }

    /** Schedules the next run RERUN_SECONDS from now, with a unique name. */
    private static void scheduleNext() {
        DateTime next = System.now().addSeconds(RERUN_SECONDS);
        String cron = '' + next.second() + ' ' + next.minute() + ' ' + next.hour()
                    + ' ' + next.day() + ' ' + next.month() + ' ? ' + next.year();
        String jobName = JOB_PREFIX + ' ' + next.getTime();
        try {
            System.schedule(jobName, cron, new AuthDocGenScheduler());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[AuthDocGenScheduler] reschedule failed: ' + e.getMessage());
        }
    }
}