public without sharing class S3LambdaService {
    private static String KEY_PREFIX = 'intakes/';
    private static Decimal UPLOAD_EXPIRY_SECONDS = 3600;
    private static Decimal DOWNLOAD_EXPIRY_SECONDS = 3600;

    public class S3Exception extends Exception {
    }

    private static Map<String, Object> call(Map<String, Object> payload) {
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('callout:AWS_Lambda_NC/presign');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(30000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new S3Exception('Lambda error ' + res.getStatusCode() + ': ' + res.getBody());
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    // ── Pre-sign: single PUT ────────────────────────────────────────
    public static String presignPut(String s3Key, String contentType) {
        Map<String, Object> res = call(
            new Map<String, Object>{
                'action' => 'put',
                'key' => s3Key,
                'contentType' => contentType,
                'expiresIn' => (Integer) UPLOAD_EXPIRY_SECONDS
            }
        );
        return (String) res.get('url');
    }

    // ── Pre-sign: GET (download) ────────────────────────────────────
    public static String presignGet(String s3Key, String fileName) {
        Map<String, Object> res = call(
            new Map<String, Object>{
                'action' => 'get',
                'key' => s3Key,
                'fileName' => fileName,
                'expiresIn' => (Integer) DOWNLOAD_EXPIRY_SECONDS
            }
        );
        return (String) res.get('url');
    }

    // ── Pre-sign: view inline (no Content-Disposition — browser renders inline) ──
    public static String presignView(String s3Key) {
        Map<String, Object> res = call(
            new Map<String, Object>{ 'action' => 'view', 'key' => s3Key, 'expiresIn' => 900 }
        );
        return (String) res.get('url');
    }

    // ── Delete ──────────────────────────────────────────────────────
    public static void deleteObject(String s3Key) {
        call(new Map<String, Object>{ 'action' => 'delete', 'key' => s3Key });
    }

    // ── Multipart: create ───────────────────────────────────────────
    public static String multipartCreate(String s3Key, String contentType) {
        Map<String, Object> res = call(
            new Map<String, Object>{ 'action' => 'multipart_create', 'key' => s3Key, 'contentType' => contentType }
        );
        return (String) res.get('uploadId');
    }

    // ── Multipart: pre-sign a batch of parts ────────────────────────
    // Returns List<Map> with {partNumber, url}
    public static List<Object> multipartPartBatch(String s3Key, String uploadId, List<Integer> partNumbers) {
        Map<String, Object> res = call(
            new Map<String, Object>{
                'action' => 'multipart_part_batch',
                'key' => s3Key,
                'uploadId' => uploadId,
                'partNumbers' => partNumbers,
                'expiresIn' => (Integer) DOWNLOAD_EXPIRY_SECONDS
            }
        );
        return (List<Object>) res.get('urls');
    }

    // ── Multipart: complete ──────────────────────────────────────────
    // parts = [{PartNumber, ETag}, ...]
    public static void multipartComplete(String s3Key, String uploadId, List<Map<String, Object>> parts) {
        call(
            new Map<String, Object>{
                'action' => 'multipart_complete',
                'key' => s3Key,
                'uploadId' => uploadId,
                'parts' => parts
            }
        );
    }

    // ── Multipart: abort ─────────────────────────────────────────────
    public static void multipartAbort(String s3Key, String uploadId) {
        call(new Map<String, Object>{ 'action' => 'multipart_abort', 'key' => s3Key, 'uploadId' => uploadId });
    }

    // ── Build an S3 key from prefix + Intake Id + UUID ──────────────
    public static String buildKey(Id intakeId, String fileName) {
        String prefix = KEY_PREFIX;
        String uid = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 16);
        String ext = fileName.contains('.') ? fileName.substringAfterLast('.') : '';
        return prefix + intakeId + '/' + uid + (String.isNotBlank(ext) ? '.' + ext : '');
    }
}