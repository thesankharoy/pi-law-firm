/**
 * IntakeSpamFilterController
 *
 * @AuraEnabled façade for the intakeSpamBin LWC.
 *  - getSpamBin()      — paginated quarantined intakes
 *  - recoverIntake()   — specialist overrides → Real
 *  - confirmSpam()     — specialist confirms verdict
 *  - purgeOldSpam()    — admin hard-deletes spam older than 30 days
 *  - getTriageStats()  — badge counts for LWC header
 */
public with sharing class IntakeSpamFilterController {

    static final Set<String> BIN_STATUSES = new Set<String>{
        'Spam', 'Junk', 'Needs Review', 'Pending AI Review'
    };
    static final Integer PURGE_THRESHOLD_DAYS = 30;
    static final String  CONFIRMED_MARKER     = 'Confirmed by specialist';

    // ══════════════════════════════════════════════════════════════════════════
    //  GET SPAM BIN — paginated + filterable
    // ══════════════════════════════════════════════════════════════════════════
    @AuraEnabled(cacheable=false)
    public static BinPage getSpamBin(String statusFilter, Integer pageSize, Integer pageNum) {
        Integer size   = (pageSize != null && pageSize > 0) ? pageSize : 25;
        Integer offset = (pageNum  != null && pageNum  > 1) ? (pageNum - 1) * size : 0;

        Boolean useFilter = String.isNotBlank(statusFilter) && BIN_STATUSES.contains(statusFilter);

        String countSoql = 'SELECT COUNT() FROM Intake__c WHERE Lead_Triage_Status__c IN :BIN_STATUSES' +
                           (useFilter ? ' AND Lead_Triage_Status__c = :statusFilter' : '');
        Integer total = Database.countQuery(countSoql);

        String dataSoql =
            'SELECT Id, Name, Lead_Triage_Status__c, ' +
            '       AI_Triage_Verdict__c, AI_Triage_Confidence__c, AI_Triage_Reason__c, ' +
            '       AI_Triage_Timestamp__c, Triage_Score__c, Triage_Signals__c, ' +
            '       Submitter_First_Name__c, Submitter_Last_Name__c, ' +
            '       Submitter_Email__c, Submitter_Phone__c, ' +
            '       Incident_Type__c, Incident_Date__c, Source__c, ' +
            '       Incident_Description__c, CreatedDate, Status__c ' +
            'FROM   Intake__c ' +
            'WHERE  Lead_Triage_Status__c IN :BIN_STATUSES ' +
            (useFilter ? 'AND Lead_Triage_Status__c = :statusFilter ' : '') +
            'ORDER BY CreatedDate DESC ' +
            'LIMIT :size OFFSET :offset';

        List<Intake__c> records = Database.query(dataSoql);

        BinPage pg     = new BinPage();
        pg.records     = toRowDTOs(records);
        pg.total       = total;
        pg.pageNum     = pageNum != null ? pageNum : 1;
        pg.pageSize    = size;
        return pg;
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  RECOVER — override to Real
    // ══════════════════════════════════════════════════════════════════════════
    @AuraEnabled
    public static void recoverIntake(Id intakeId) {
        Intake__c intake = [
            SELECT Id, Status__c, Lead_Triage_Status__c
            FROM   Intake__c
            WHERE  Id = :intakeId
            LIMIT  1
        ];
        intake.Lead_Triage_Status__c = 'Real';
        intake.AI_Triage_Verdict__c  = 'Real';
        intake.AI_Triage_Reason__c   = 'Manually recovered by specialist ' +
                                       UserInfo.getName() + ' on ' + System.now().format();
        update intake;
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  CONFIRM SPAM — specialist confirms verdict
    // ══════════════════════════════════════════════════════════════════════════
    @AuraEnabled
    public static void confirmSpam(Id intakeId, String statusConfirmed) {
        Set<String> allowed = new Set<String>{ 'Spam', 'Junk', 'Needs Review' };
        if (!allowed.contains(statusConfirmed)) {
            throw new AuraHandledException('Invalid status: ' + statusConfirmed);
        }
        Intake__c upd = new Intake__c(
            Id                    = intakeId,
            Lead_Triage_Status__c = statusConfirmed,
            AI_Triage_Reason__c   = CONFIRMED_MARKER + ' ' + UserInfo.getName() +
                                    ' on ' + System.now().format()
        );
        update upd;
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  PURGE — admin hard-delete confirmed spam older than PURGE_THRESHOLD_DAYS
    //  Requires Custom Permission 'Intake_Admin'.
    //
    //  NOTE: AI_Triage_Reason__c is a long text area field and cannot be
    //  filtered/LIKE'd in SOQL, so the "confirmed by specialist" check is
    //  done in Apex after querying the date-bounded candidate set.
    // ══════════════════════════════════════════════════════════════════════════
    @AuraEnabled
    public static Integer purgeOldSpam() {
        if (!FeatureManagement.checkPermission('Intake_Admin')) {
            throw new AuraHandledException('Only Intake Admins can purge spam records.');
        }
        DateTime cutoff = System.now().addDays(-PURGE_THRESHOLD_DAYS);
        List<Intake__c> candidates = [
            SELECT Id, AI_Triage_Reason__c
            FROM   Intake__c
            WHERE  Lead_Triage_Status__c = 'Spam'
            AND    AI_Triage_Timestamp__c < :cutoff
            LIMIT  200
        ];

        List<Intake__c> toDelete = new List<Intake__c>();
        for (Intake__c i : candidates) {
            if (String.isNotBlank(i.AI_Triage_Reason__c) &&
                i.AI_Triage_Reason__c.contains(CONFIRMED_MARKER)) {
                toDelete.add(i);
            }
        }

        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        return toDelete.size();
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  STATS — badge counts for LWC header
    // ══════════════════════════════════════════════════════════════════════════
    @AuraEnabled(cacheable=false)
    public static TriageStats getTriageStats() {
        AggregateResult[] counts = [
            SELECT Lead_Triage_Status__c status, COUNT(Id) cnt
            FROM   Intake__c
            WHERE  Lead_Triage_Status__c IN :BIN_STATUSES
            GROUP BY Lead_Triage_Status__c
        ];

        TriageStats stats = new TriageStats();
        for (AggregateResult ar : counts) {
            String  status = (String)  ar.get('status');
            Integer cnt    = Integer.valueOf(ar.get('cnt'));
            switch on status {
                when 'Spam'              { stats.spamCount        = cnt; }
                when 'Junk'              { stats.junkCount        = cnt; }
                when 'Needs Review'      { stats.needsReviewCount = cnt; }
                when 'Pending AI Review' { stats.pendingCount     = cnt; }
            }
        }
        stats.totalBin = stats.spamCount + stats.junkCount +
                         stats.needsReviewCount + stats.pendingCount;
        return stats;
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  DTOs
    // ══════════════════════════════════════════════════════════════════════════
    public class BinPage {
        @AuraEnabled public List<BinRowDTO> records;
        @AuraEnabled public Integer         total;
        @AuraEnabled public Integer         pageNum;
        @AuraEnabled public Integer         pageSize;
    }

    public class BinRowDTO {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  triageStatus;
        @AuraEnabled public String  aiVerdict;
        @AuraEnabled public Decimal aiConfidence;
        @AuraEnabled public String  aiReason;
        @AuraEnabled public String  aiTimestamp;
        @AuraEnabled public Integer triageScore;
        @AuraEnabled public String  triageSignals;
        @AuraEnabled public String  submitterName;
        @AuraEnabled public String  email;
        @AuraEnabled public String  phone;
        @AuraEnabled public String  incidentType;
        @AuraEnabled public String  incidentDate;
        @AuraEnabled public String  source;
        @AuraEnabled public String  description;
        @AuraEnabled public String  createdDate;
    }

    public class TriageStats {
        @AuraEnabled public Integer spamCount        = 0;
        @AuraEnabled public Integer junkCount        = 0;
        @AuraEnabled public Integer needsReviewCount = 0;
        @AuraEnabled public Integer pendingCount     = 0;
        @AuraEnabled public Integer totalBin         = 0;
    }

    static List<BinRowDTO> toRowDTOs(List<Intake__c> records) {
        List<BinRowDTO> rows = new List<BinRowDTO>();
        for (Intake__c i : records) {
            BinRowDTO row       = new BinRowDTO();
            row.id              = i.Id;
            row.name            = i.Name;
            row.triageStatus    = i.Lead_Triage_Status__c;
            row.aiVerdict       = i.AI_Triage_Verdict__c;
            row.aiConfidence    = i.AI_Triage_Confidence__c != null
                                  ? (i.AI_Triage_Confidence__c * 100).setScale(0) : null;
            row.aiReason        = i.AI_Triage_Reason__c;
            row.aiTimestamp     = i.AI_Triage_Timestamp__c != null
                                  ? i.AI_Triage_Timestamp__c.format() : '';
            row.triageScore     = i.Triage_Score__c != null ? Integer.valueOf(i.Triage_Score__c) : 0;
            row.triageSignals   = i.Triage_Signals__c;
            row.submitterName   = (safeStr(i.Submitter_First_Name__c) + ' ' +
                                   safeStr(i.Submitter_Last_Name__c)).trim();
            row.email           = i.Submitter_Email__c;
            row.phone           = i.Submitter_Phone__c;
            row.incidentType    = i.Incident_Type__c;
            row.incidentDate    = i.Incident_Date__c != null
                                  ? String.valueOf(i.Incident_Date__c) : '';
            row.source          = i.Source__c;
            row.description     = i.Incident_Description__c != null
                                  ? i.Incident_Description__c.abbreviate(200) : '';
            row.createdDate     = i.CreatedDate.format();
            rows.add(row);
        }
        return rows;
    }

    static String safeStr(String s) { return s == null ? '' : s; }
}