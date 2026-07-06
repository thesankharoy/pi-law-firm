public with sharing class IntakeSpamFilterController {

    static final String STATUS_SPAM = 'Spam';
    static final String STATUS_NEW  = 'New';

    // ══════════════════════════════════════════════════════════════════════════
    //  GET SPAM BIN — paginated
    // ══════════════════════════════════════════════════════════════════════════
    @AuraEnabled(cacheable=false)
    public static BinPage getSpamBin(Integer pageSize, Integer pageNum) {
        Integer size   = (pageSize != null && pageSize > 0) ? pageSize : 25;
        Integer offset = (pageNum  != null && pageNum  > 1) ? (pageNum - 1) * size : 0;

        Integer total = [SELECT COUNT() FROM Intake__c WHERE Status__c = :STATUS_SPAM];

        List<Intake__c> records = [
            SELECT Id, Name, Status__c,
                   AI_Triage_Verdict__c, AI_Triage_Confidence__c, AI_Triage_Reason__c,
                   AI_Triage_Timestamp__c, Triage_Score__c, Triage_Signals__c,
                   Submitter_First_Name__c, Submitter_Last_Name__c,
                   Submitter_Email__c, Submitter_Phone__c,
                   Incident_Type__c, Incident_Date__c, Source__c,
                   Incident_Description__c, CreatedDate
            FROM   Intake__c
            WHERE  Status__c = :STATUS_SPAM
            ORDER BY CreatedDate DESC
            LIMIT :size OFFSET :offset
        ];

        BinPage pg  = new BinPage();
        pg.records  = toRowDTOs(records);
        pg.total    = total;
        pg.pageNum  = pageNum != null ? pageNum : 1;
        pg.pageSize = size;
        return pg;
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  RECOVER — this is a real lead, send it back to New Intake (not Active)
    // ══════════════════════════════════════════════════════════════════════════
    @AuraEnabled
    public static void recoverIntake(Id intakeId) {
        Intake__c upd = new Intake__c(
            Id                  = intakeId,
            Status__c           = STATUS_NEW,
            AI_Triage_Reason__c = 'Manually recovered by specialist ' +
                                  UserInfo.getName() + ' on ' + System.now().format()
        );
        update upd;
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  DELETE SPAM — specialist confirms it's spam, record is deleted immediately
    // ══════════════════════════════════════════════════════════════════════════
    @AuraEnabled
    public static void deleteSpam(Id intakeId) {
        Intake__c intake = [
            SELECT Id, Status__c
            FROM   Intake__c
            WHERE  Id = :intakeId
            LIMIT  1
        ];
        if (intake.Status__c != STATUS_SPAM) {
            throw new AuraHandledException('Only records currently flagged as Spam can be deleted from this bin.');
        }
        delete intake;
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  STATS — badge count for LWC header
    // ══════════════════════════════════════════════════════════════════════════
    @AuraEnabled(cacheable=false)
    public static Integer getSpamCount() {
        return [SELECT COUNT() FROM Intake__c WHERE Status__c = :STATUS_SPAM];
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

    static List<BinRowDTO> toRowDTOs(List<Intake__c> records) {
        List<BinRowDTO> rows = new List<BinRowDTO>();
        for (Intake__c i : records) {
            BinRowDTO row       = new BinRowDTO();
            row.id              = i.Id;
            row.name            = i.Name;
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