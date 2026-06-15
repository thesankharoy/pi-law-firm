public class TwilioTokenEndpointController {
    public String getToken() {
        return TwilioTokenService.getToken(); // reuses your existing Apex class
    }
}