/**
 * IntakeDocPdfRenderer
 *
 * The Automated Process user cannot render Visualforce (its license has no VF
 * entitlement — that is why getContent() throws "insufficient privileges to
 * access the controller"). So instead of rendering locally, we fetch the
 * already-rendered PDF over an authenticated HTTP callout to this same org,
 * through the existing "Salesforce NC" Named Credential.
 *
 * The page renders as the Named Credential's LICENSED principal user, so VF
 * works; the controllers are `without sharing`, so that user reads the Intake
 * data fine. The Automated Process caller only receives the PDF bytes.
 *
 * REQUIREMENT: "Salesforce NC" (callout:Salesforce_NC) must authenticate as a
 * Salesforce-licensed user that can access the three PDF pages, their
 * controllers, and Intake/Role/Contact/Organization data. That user needs
 * Visualforce Page Access + Apex Class Access to the three controllers.
 */
public without sharing class IntakeDocPdfRenderer {

    // If your Named Credential's API name differs from "Salesforce_NC", change it here.
    private static final String NAMED_CRED = 'callout:Salesforce_NC';

    public class RenderException extends Exception {}

    public static Blob renderPdf(String pageName, Id intakeId) {
        String endpoint = NAMED_CRED + '/apex/' + pageName + '?Id=' + intakeId;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);
        Integer sc = res.getStatusCode();

        if (sc != 200) {
            throw new RenderException('VF render failed for ' + pageName
                + ' — HTTP ' + sc + ' : ' + safeSnippet(res.getBody()));
        }

        // A login redirect / access error comes back as HTML, not a PDF.
        String ct = res.getHeader('Content-Type');
        if (ct != null && ct.containsIgnoreCase('html')) {
            throw new RenderException('Got HTML instead of PDF for ' + pageName
                + ' — the Salesforce_NC callout is not authenticated as a licensed '
                + 'user (login redirect). Point its named principal at a '
                + 'Salesforce-licensed user with access to the page. First bytes: '
                + safeSnippet(res.getBody()));
        }

        Blob pdf = res.getBodyAsBlob();
        if (pdf == null || pdf.size() == 0) {
            throw new RenderException('VF render returned an empty body for ' + pageName);
        }
        return pdf;
    }

    private static String safeSnippet(String body) {
        if (String.isBlank(body)) return '(empty)';
        return body.length() > 300 ? body.substring(0, 300) : body;
    }
}