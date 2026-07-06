public with sharing class DocumentFlagsController {

    // ─── Public DTOs ─────────────────────────────────────────────────────────

    public class DocumentFlag {
        @AuraEnabled public String  docType    { get; set; }
        @AuraEnabled public String  priority   { get; set; }   // HIGH / MEDIUM / LOW
        @AuraEnabled public String  reason     { get; set; }
        @AuraEnabled public Boolean isPresent  { get; set; }
        @AuraEnabled public String  uploadedAt { get; set; }   // 'YYYY-MM-DD' or null
        @AuraEnabled public String  docName    { get; set; }   // file name if present
    }

    public class FlagsResult {
        @AuraEnabled public List<DocumentFlag> missing      { get; set; }
        @AuraEnabled public List<DocumentFlag> present      { get; set; }
        @AuraEnabled public Integer            totalReq     { get; set; }
        @AuraEnabled public Integer            totalDone    { get; set; }
        @AuraEnabled public String             incidentType { get; set; }
        @AuraEnabled public String             intakeName   { get; set; }
    }

    // ─── Priority + reason overrides ─────────────────────────────────────────
    // Any Document_Type__c value NOT listed here gets priority = LOW and a
    // generic reason. Add entries here to promote/demote specific doc types.

    private static final Map<String, String[]> PRIORITY_MAP = new Map<String, String[]>{
        // [priority, reason]
        'HIPAA Authorization'          => new String[]{ 'HIGH',   'Required to obtain any medical records on the client\'s behalf.' },
        'Letter of Representation'     => new String[]{ 'HIGH',   'Notifies all carriers and providers the firm represents the client.' },
        'Retainer Agreement'           => new String[]{ 'HIGH',   'Signed engagement — case cannot proceed without this.' },
        'Medical Records'              => new String[]{ 'HIGH',   'Primary evidence of injury; essential for the demand package.' },
        'Medical Bills'                => new String[]{ 'HIGH',   'Documents economic damages (specials).' },
        'Police Report'                => new String[]{ 'HIGH',   'Establishes fault and official incident record for carriers.' },
        'Insurance Correspondence'     => new String[]{ 'HIGH',   'Claim numbers and adjuster contacts — needed immediately.' },
        'Photos — Scene'               => new String[]{ 'HIGH',   'Preserves scene evidence before conditions change.' },
        'Photos — Injury'              => new String[]{ 'HIGH',   'Visual documentation of client injuries for the demand package.' },
        'Authorization Form'           => new String[]{ 'HIGH',   'Required by medical facilities and workers comp boards.' },
        'Demand Letter'                => new String[]{ 'MEDIUM', 'Sent to opposing carrier — triggers settlement negotiation.' },
        'Expert Report'                => new String[]{ 'MEDIUM', 'Standard-of-care or engineering opinion for complex liability.' },
        'Employment Records'           => new String[]{ 'MEDIUM', 'Wage and hour records for lost-income calculation.' },
        'Lien Documentation'           => new String[]{ 'MEDIUM', 'Tracks medical liens that must be resolved at settlement.' },
        'Settlement Agreement'         => new String[]{ 'MEDIUM', 'Final agreement — required to close the matter.' },
        'Court Filing — Complaint'     => new String[]{ 'LOW',    'Filed if settlement fails and litigation proceeds.' },
        'Court Filing — Answer'        => new String[]{ 'LOW',    'Defendant response — needed once complaint is filed.' },
        'Discovery — Interrogatories'  => new String[]{ 'LOW',    'Written discovery requests — litigation phase.' },
        'Discovery — Deposition'       => new String[]{ 'LOW',    'Deposition transcripts — litigation phase.' },
        'Other'                        => new String[]{ 'LOW',    'Any additional supporting documentation.' }
    };

    // ─── Priority sort order ──────────────────────────────────────────────────

    private static final Map<String, Integer> PRIORITY_ORDER = new Map<String, Integer>{
        'HIGH'   => 0,
        'MEDIUM' => 1,
        'LOW'    => 2
    };

    // ─── Main entry point ─────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static FlagsResult getDocumentFlags(Id intakeId) {
        try {

            // 1. Load intake
            Intake__c intake = [
                SELECT Name, Incident_Type__c
                FROM   Intake__c
                WHERE  Id = :intakeId
                LIMIT  1
            ];

            // 2. Get ALL active picklist values from Document_Type__c dynamically
            //    so the list auto-updates when picklist values are added in Setup.
            List<String> allDocTypes = new List<String>();
            Schema.DescribeFieldResult dfr = Schema.SObjectType.Document__c
                .fields.getMap()
                .get('Document_Type__c')
                .getDescribe();
            for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                if (pe.isActive()) {
                    allDocTypes.add(pe.getValue());
                }
            }

            // 3. Load documents already on file for this intake
            List<Document__c> existingDocs = [
                SELECT Name, Document_Type__c, Status__c, CreatedDate
                FROM   Document__c
                WHERE  Intake__c  = :intakeId
                  AND  Status__c IN ('Active', 'Generated')
                ORDER BY CreatedDate ASC
            ];

            // Build lookup: docType → first matching Document__c (earliest uploaded)
            Map<String, Document__c> presentByType = new Map<String, Document__c>();
            for (Document__c d : existingDocs) {
                if (String.isNotBlank(d.Document_Type__c) &&
                    !presentByType.containsKey(d.Document_Type__c)) {
                    presentByType.put(d.Document_Type__c, d);
                }
            }

            // 4. Diff: every picklist value is required
            List<DocumentFlag> presentFlags = new List<DocumentFlag>();
            List<DocumentFlag> missingFlags = new List<DocumentFlag>();

            for (String docType : allDocTypes) {
                String[] meta     = PRIORITY_MAP.containsKey(docType)
                    ? PRIORITY_MAP.get(docType)
                    : new String[]{ 'LOW', 'Supporting document for this case.' };
                String   priority = meta[0];
                String   reason   = meta[1];

                DocumentFlag flag = new DocumentFlag();
                flag.docType      = docType;
                flag.priority     = priority;
                flag.reason       = reason;

                if (presentByType.containsKey(docType)) {
                    Document__c d  = presentByType.get(docType);
                    flag.isPresent  = true;
                    flag.docName    = d.Name;
                    flag.uploadedAt = String.valueOf(d.CreatedDate.date());
                    presentFlags.add(flag);
                } else {
                    flag.isPresent  = false;
                    flag.docName    = null;
                    flag.uploadedAt = null;
                    missingFlags.add(flag);
                }
            }

            // Sort missing: HIGH → MEDIUM → LOW, then alphabetically within each tier
            missingFlags.sort(new FlagComparator());
            presentFlags.sort(new FlagComparator());

            FlagsResult result    = new FlagsResult();
            result.missing        = missingFlags;
            result.present        = presentFlags;
            result.totalReq       = allDocTypes.size();
            result.totalDone      = presentFlags.size();
            result.incidentType   = String.isNotBlank(intake.Incident_Type__c)
                                    ? intake.Incident_Type__c : 'Not specified';
            result.intakeName     = intake.Name;
            return result;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('DocumentFlagsController: ' + e.getMessage());
        }
    }

    // ─── Comparator: HIGH first, then MEDIUM, then LOW; alpha within tier ────

    private class FlagComparator implements Comparator<DocumentFlag> {
        public Integer compare(DocumentFlag a, DocumentFlag b) {
            Integer aP = PRIORITY_ORDER.containsKey(a.priority) ? PRIORITY_ORDER.get(a.priority) : 99;
            Integer bP = PRIORITY_ORDER.containsKey(b.priority) ? PRIORITY_ORDER.get(b.priority) : 99;
            if (aP != bP) return aP - bP;
            // Same priority → alphabetical
            return a.docType.compareTo(b.docType);
        }
    }
}