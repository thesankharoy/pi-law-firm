global class TwilioTokenServiceVF {

    @RemoteAction
    global static String getToken() {

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://salesforce-softphone-9217.twil.io/token');
        req.setMethod('GET');

        Http http = new Http();
        HttpResponse res = http.send(req);

        String body = res.getBody();

        // Temporary debug — check Salesforce debug logs for this
        System.debug('TOKEN BODY: ' + body);
        System.debug('STATUS: ' + res.getStatusCode());

        return body;
    }

    @RemoteAction
    global static String getIntakePhone(String intakeId) {
        if (String.isBlank(intakeId)) return '';
        List<Intake__c> intakes = [
            SELECT Intake_Phone__c FROM Intake__c WHERE Id = :intakeId LIMIT 1
        ];
        if (!intakes.isEmpty() && intakes[0].Intake_Phone__c != null) {
            return intakes[0].Intake_Phone__c;
        }
        return '';
    }

    global class CallerInfo {
        global Boolean found = false;
        global String contactId;
        global String name;
        global String email;
        global String intakeId;
        global String intakeName;
        global String status;
        global String incidentType;
        global Integer intakeCount = 0;
    }

    /**
     * Live inbound caller lookup. Matches the incoming number against Contact
     * phone-digit fields and returns whether they're an existing client plus
     * their most recent Intake. Called on every incoming call.
     */
    @RemoteAction
    global static CallerInfo lookupCaller(String phoneNumber) {
        CallerInfo info = new CallerInfo();
        if (String.isBlank(phoneNumber)) return info;

        String digits = phoneNumber.replaceAll('[^0-9]', '');
        if (digits.length() < 7) return info;
        // Match on the last 10 digits to ignore country-code/format differences.
        String last10 = digits.length() >= 10 ? digits.substring(digits.length() - 10) : digits;
        String pat = '%' + last10;

        List<Contact> cons = [
            SELECT Id, Name, Email
            FROM Contact
            WHERE Phone LIKE :pat OR MobilePhone LIKE :pat
            LIMIT 1
        ];
        if (cons.isEmpty()) return info;

        Contact c = cons[0];
        info.found = true;
        info.contactId = c.Id;
        info.name = c.Name;
        info.email = c.Email;

        List<Intake__c> intakes = [
            SELECT Id, Name, Status__c, Incident_Type__c
            FROM Intake__c
            WHERE Client__c = :c.Id
            ORDER BY CreatedDate DESC
        ];
        info.intakeCount = intakes.size();
        if (!intakes.isEmpty()) {
            info.intakeId      = intakes[0].Id;
            info.intakeName    = intakes[0].Name;
            info.status        = intakes[0].Status__c;
            info.incidentType  = intakes[0].Incident_Type__c;
        }
        return info;
    }

    /**
     * Click-to-dial helper. Given the record a phone field was clicked on,
     * return the Intake Id to load into the softphone.
     *  - Intake__c  -> itself
     *  - Contact    -> their most recent open intake (fallback: most recent)
     */
    @RemoteAction
    global static String resolveIntakeId(String recordId) {
        if (String.isBlank(recordId)) return '';
        Id rid;
        try { rid = (Id) recordId; } catch (Exception e) { return ''; }

        String objType = String.valueOf(rid.getSObjectType());
        if (objType == 'Intake__c') {
            return recordId;
        }
        if (objType == 'Contact') {
            List<Intake__c> intakes = [
                SELECT Id, Status__c FROM Intake__c
                WHERE Client__c = :rid ORDER BY CreatedDate DESC
            ];
            if (intakes.isEmpty()) return '';
            Set<String> closed = new Set<String>{ 'Turned Down', 'Referred Out', 'Converted' };
            for (Intake__c i : intakes) {
                if (!closed.contains(i.Status__c)) return String.valueOf(i.Id);
            }
            return String.valueOf(intakes[0].Id);
        }
        return '';
    }

    // ---- Call button (LWC) on Contact / Intake record pages ----
    public class PhoneOption {
        @AuraEnabled public String label;
        @AuraEnabled public String phone;
    }
    public class DialInfo {
        @AuraEnabled public String intakeId;
        @AuraEnabled public List<PhoneOption> phones = new List<PhoneOption>();
    }

    @AuraEnabled(cacheable=true)
    public static DialInfo getDialInfo(Id recordId) {
        DialInfo d = new DialInfo();
        if (recordId == null) return d;
        String objType = String.valueOf(recordId.getSObjectType());

        if (objType == 'Intake__c') {
            Intake__c i = [SELECT Intake_Phone__c FROM Intake__c WHERE Id = :recordId LIMIT 1];
            d.intakeId = String.valueOf(recordId);
            addPhone(d, 'Intake Phone', i.Intake_Phone__c);
        } else if (objType == 'Contact') {
            Contact c = [SELECT MobilePhone, Phone FROM Contact WHERE Id = :recordId LIMIT 1];
            addPhone(d, 'Mobile', c.MobilePhone);
            addPhone(d, 'Phone', c.Phone);
            d.intakeId = resolveIntakeId(String.valueOf(recordId));
        }
        return d;
    }

    private static void addPhone(DialInfo d, String label, String num) {
        if (String.isNotBlank(num)) {
            PhoneOption p = new PhoneOption();
            p.label = label;
            p.phone = num;
            d.phones.add(p);
        }
    }

    // Deepgram API key. Set directly in code because the External Credential custom
    // header for "Authorization" was unreliable. For production, move this to a
    // Protected Custom Metadata record and read it here instead of hardcoding.
    private static final String DEEPGRAM_KEY = '3c0332eca2b5ec5771abb1a9eac4a295be08635d';

    @RemoteAction
    global static String getDeepgramToken() {
        // Return the raw API key for the browser's WebSocket subprotocol auth
        // (new WebSocket(url, ['token', key])) — Deepgram's documented browser method.
        // The grant-token + ['bearer'] subprotocol was rejected by the WS handshake.
        return DEEPGRAM_KEY;
    }
}