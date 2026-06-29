/**
 * Sends an S3-backed Document__c to Claude (Anthropic Messages API) for key-fact
 * extraction and caches the structured result in Document_Analysis__c so the same
 * file is never analyzed twice.
 *
 * AI path: direct Anthropic API via Named Credential `Anthropic_Claude`.
 * This is a deliberate exception to the Prompt-Builder-first rule (binary PDFs/scans
 * cannot be grounded through Prompt Builder), alongside the Live Call Co-Pilot.
 *
 * The file bytes never pass through Salesforce: Claude fetches the document itself
 * from a short-lived presigned S3 GET URL (source.type = "url").
 */
public with sharing class DocumentAnalysisService {
    public class AnalysisException extends Exception {}

    // Anthropic model used for extraction. Sonnet 4.6 = strong vision/PDF at lower cost than Opus.
    @TestVisible
    private static String MODEL = 'claude-sonnet-4-6';
    private static final String ANTHROPIC_VERSION = '2023-06-01';
    private static final Integer MAX_TOKENS = 4096;
    private static final String NC = 'callout:Anthropic_Claude/v1/messages';

    private static final String SYSTEM_PROMPT =
        'You are a paralegal assistant for a personal-injury law firm. You read a single ' +
        'document (medical record, police report, insurance letter, bill, or correspondence) ' +
        'and extract the key facts an intake specialist needs. Be accurate and never invent ' +
        'facts that are not present in the document.';

    // The extraction schema. Claude is told to return ONLY this JSON object.
    private static final String EXTRACTION_PROMPT =
        'Analyze the attached document and return ONLY a JSON object (no markdown, no prose) ' +
        'with exactly these keys:\n' +
        '{\n' +
        '  "documentType": "one of: Medical Record, Police Report, Insurance Letter, Bill/Invoice, Correspondence, Legal Filing, Other",\n' +
        '  "summary": "2-4 sentence plain-language summary",\n' +
        '  "keyDates": [{"label": "what the date is", "date": "the date as written"}],\n' +
        '  "parties": [{"name": "person or org", "role": "their role, e.g. Patient, Officer, Adjuster, Provider"}],\n' +
        '  "providers": [{"name": "facility or clinician", "type": "e.g. Hospital, PT, Imaging"}],\n' +
        '  "injuries": ["diagnosis or injury described"],\n' +
        '  "amounts": [{"label": "what the amount is for", "value": "amount as written"}],\n' +
        '  "identifiers": [{"label": "Policy Number / Claim Number / Case Number / MRN", "value": "the value"}],\n' +
        '  "actionItems": ["follow-up an intake specialist should take"]\n' +
        '}\n' +
        'Use empty arrays for sections with no data. Return the JSON object and nothing else.';

    // ── DTO returned to the LWC ──────────────────────────────────────
    public class AnalysisDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Id documentId;
        @AuraEnabled public String documentName;
        @AuraEnabled public String status;
        @AuraEnabled public String documentType;
        @AuraEnabled public String summary;
        @AuraEnabled public String extractedJson;
        @AuraEnabled public String model;
        @AuraEnabled public String analyzedOnLabel;
        @AuraEnabled public Integer inputTokens;
        @AuraEnabled public Integer outputTokens;
        @AuraEnabled public String errorMessage;
    }

    // ── Cache lookup ─────────────────────────────────────────────────
    /** Returns the cached completed analysis for a document, or null. */
    public static AnalysisDTO getCached(Id documentId) {
        List<Document_Analysis__c> existing = [
            SELECT Id, Document__c, Document__r.Name, Status__c, Document_Type__c, Summary__c,
                   Extracted_JSON__c, Model__c, Analyzed_On__c, Input_Tokens__c, Output_Tokens__c, Error__c
            FROM Document_Analysis__c
            WHERE Document__c = :documentId AND Status__c = 'Completed'
            ORDER BY Analyzed_On__c DESC NULLS LAST
            LIMIT 1
        ];
        return existing.isEmpty() ? null : toDTO(existing[0]);
    }

    // ── Main entry point ─────────────────────────────────────────────
    /**
     * Returns the cached analysis when available (unless force=true), otherwise
     * calls Claude, persists, and returns the fresh analysis.
     */
    public static AnalysisDTO analyze(Id documentId, Boolean force) {
        if (!force) {
            AnalysisDTO cached = getCached(documentId);
            if (cached != null) return cached;
        }

        Document__c doc = [
            SELECT Id, Name, S3_Key__c, MIME_Type__c, Intake__c, Status__c
            FROM Document__c
            WHERE Id = :documentId
            LIMIT 1
        ];

        String blockType = mediaBlockType(doc.Name, doc.MIME_Type__c);
        if (blockType == null) {
            throw new AuraHandledException(
                'This file type can\'t be analyzed yet. ' +
                'Supported: PDF and images (PNG, JPEG, GIF, WebP).');
        }

        // Use an ASCII-safe name (the S3 key's basename) for the presign. The real
        // file name can contain non-Latin-1 chars (e.g. macOS screenshots use a U+202F
        // narrow no-break space), which S3 rejects in the response-content-disposition
        // header — and Claude only needs the bytes, not the download filename.
        String safeName = doc.S3_Key__c.substringAfterLast('/');
        String presignedUrl = S3LambdaService.presignGet(doc.S3_Key__c, safeName);

        Document_Analysis__c record = existingRecord(documentId);
        if (record == null) {
            record = new Document_Analysis__c(Document__c = documentId);
        }
        record.Intake__c = doc.Intake__c;
        record.Model__c = MODEL;

        try {
            ClaudeResult cr = callClaude(blockType, presignedUrl);

            Map<String, Object> facts = parseFacts(cr.text);
            record.Status__c = 'Completed';
            record.Extracted_JSON__c = JSON.serializePretty(facts);
            record.Summary__c = asString(facts.get('summary'));
            record.Document_Type__c = trim(asString(facts.get('documentType')), 120);
            record.Analyzed_On__c = System.now();
            record.Input_Tokens__c = cr.inputTokens;
            record.Output_Tokens__c = cr.outputTokens;
            record.Error__c = null;
            upsert record;
            return toDTO(record);
        } catch (Exception e) {
            record.Status__c = 'Failed';
            record.Error__c = e.getMessage();
            record.Analyzed_On__c = System.now();
            try {
                upsert record;
            } catch (Exception ignore) {
                /* never let bookkeeping mask the real error */
            }
            throw new AuraHandledException('Analysis failed: ' + e.getMessage());
        }
    }

    // ── Anthropic callout ────────────────────────────────────────────
    private class ClaudeResult {
        String text;
        Integer inputTokens;
        Integer outputTokens;
    }

    private static ClaudeResult callClaude(String blockType, String presignedUrl) {
        // Build the request as typed structures so JSON.serialize handles all escaping.
        Map<String, Object> mediaBlock = new Map<String, Object>{
            'type' => blockType,
            'source' => new Map<String, Object>{ 'type' => 'url', 'url' => presignedUrl }
        };
        Map<String, Object> textBlock = new Map<String, Object>{
            'type' => 'text',
            'text' => EXTRACTION_PROMPT
        };
        Map<String, Object> userMsg = new Map<String, Object>{
            'role' => 'user',
            'content' => new List<Object>{ mediaBlock, textBlock }
        };
        Map<String, Object> body = new Map<String, Object>{
            'model' => MODEL,
            'max_tokens' => MAX_TOKENS,
            'system' => SYSTEM_PROMPT,
            'messages' => new List<Object>{ userMsg }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NC);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('anthropic-version', ANTHROPIC_VERSION);
        // x-api-key is injected by the `Anthropic_Claude` External Credential (Custom header).
        req.setTimeout(120000);
        req.setBody(JSON.serialize(body));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AnalysisException(
                'Anthropic API returned HTTP ' + res.getStatusCode() + ': ' + res.getBody());
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        // Concatenate any text content blocks.
        String text = '';
        for (Object o : (List<Object>) parsed.get('content')) {
            Map<String, Object> blk = (Map<String, Object>) o;
            if (blk.get('type') == 'text') {
                text += String.valueOf(blk.get('text'));
            }
        }
        if (String.isBlank(text)) {
            throw new AnalysisException('Anthropic API returned no text content.');
        }

        ClaudeResult cr = new ClaudeResult();
        cr.text = text;
        Map<String, Object> usage = (Map<String, Object>) parsed.get('usage');
        if (usage != null) {
            cr.inputTokens = toInt(usage.get('input_tokens'));
            cr.outputTokens = toInt(usage.get('output_tokens'));
        }
        return cr;
    }

    // ── Helpers ──────────────────────────────────────────────────────
    private static final Set<String> IMAGE_EXTS =
        new Set<String>{ 'png', 'jpg', 'jpeg', 'gif', 'webp' };

    /** True when Claude can read the file (PDF or image). */
    public static Boolean isAnalyzable(String fileName, String mime) {
        return mediaBlockType(fileName, mime) != null;
    }

    /**
     * Maps a file to the Anthropic content block type ('document' | 'image'), or null.
     * Filename extension is authoritative because Document__c.MIME_Type__c is only
     * 10 chars in this org and truncates longer MIME types (e.g. application/pdf).
     */
    @TestVisible
    private static String mediaBlockType(String fileName, String mime) {
        String ext = extOf(fileName);
        if (ext == 'pdf') return 'document';
        if (IMAGE_EXTS.contains(ext)) return 'image';

        // Fallback: short MIME types that do fit the field.
        if (String.isNotBlank(mime)) {
            String m = mime.toLowerCase();
            if (m == 'application/pdf') return 'document';
            if (m == 'image/png' || m == 'image/jpeg' || m == 'image/jpg' ||
                m == 'image/gif' || m == 'image/webp') {
                return 'image';
            }
        }
        return null;
    }

    private static String extOf(String fileName) {
        if (String.isBlank(fileName)) return '';
        Integer dot = fileName.lastIndexOf('.');
        return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    }

    /** Strips markdown fences / prose and parses the JSON object Claude returned. */
    @TestVisible
    private static Map<String, Object> parseFacts(String raw) {
        String s = raw == null ? '' : raw.trim();
        Integer startIdx = s.indexOf('{');
        Integer endIdx = s.lastIndexOf('}');
        if (startIdx < 0 || endIdx <= startIdx) {
            throw new AnalysisException('Could not find a JSON object in the model response.');
        }
        return (Map<String, Object>) JSON.deserializeUntyped(s.substring(startIdx, endIdx + 1));
    }

    private static Document_Analysis__c existingRecord(Id documentId) {
        // Select the fields toDTO() reads so the re-analyze path can build a DTO
        // without re-querying.
        List<Document_Analysis__c> rows = [
            SELECT Id, Document__c, Document__r.Name
            FROM Document_Analysis__c
            WHERE Document__c = :documentId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static AnalysisDTO toDTO(Document_Analysis__c r) {
        AnalysisDTO d = new AnalysisDTO();
        d.id = r.Id;
        d.documentId = r.Document__c;
        d.documentName = r.Document__r != null ? r.Document__r.Name : null;
        d.status = r.Status__c;
        d.documentType = r.Document_Type__c;
        d.summary = r.Summary__c;
        d.extractedJson = r.Extracted_JSON__c;
        d.model = r.Model__c;
        d.analyzedOnLabel = r.Analyzed_On__c == null
            ? null
            : r.Analyzed_On__c.format('MMM d, yyyy, h:mm a');
        d.inputTokens = r.Input_Tokens__c == null ? null : Integer.valueOf(r.Input_Tokens__c);
        d.outputTokens = r.Output_Tokens__c == null ? null : Integer.valueOf(r.Output_Tokens__c);
        d.errorMessage = r.Error__c;
        return d;
    }

    private static String asString(Object o) {
        return o == null ? null : String.valueOf(o);
    }
    private static String trim(String s, Integer len) {
        if (s == null) return null;
        return s.length() > len ? s.substring(0, len) : s;
    }
    private static Integer toInt(Object o) {
        return o == null ? null : Integer.valueOf(String.valueOf(o));
    }
}