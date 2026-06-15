public class TestDebug {

    @InvocableMethod(label='Debug Response')
    public static void printResponse(List<String> responses) {

        for(String response : responses) {
            System.debug('========== RESPONSE ==========');
            System.debug(response);
        }
    }
}