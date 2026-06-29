/**
 * Reusable HttpCalloutMock for the Anthropic Messages API. Construct with the HTTP
 * status and the assistant text you want Claude to "return"; the mock wraps that text
 * in a well-formed Messages response (with usage) for 2xx, or an error body otherwise.
 */
@isTest
public class AnthropicCalloutMock implements HttpCalloutMock {
    private Integer status;
    private String assistantText;

    public AnthropicCalloutMock(Integer status, String assistantText) {
        this.status = status;
        this.assistantText = assistantText;
    }

    /** Builds a Messages-API success body whose single text block is `text`. */
    public static String successBody(String text) {
        return '{"content":[{"type":"text","text":"' + escape(text) + '"}],'
            + '"model":"claude-sonnet-4-6","usage":{"input_tokens":200,"output_tokens":80}}';
    }

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(status);
        res.setBody(status >= 200 && status < 300
            ? successBody(assistantText)
            : '{"error":{"message":"bad request"}}');
        return res;
    }

    private static String escape(String s) {
        return s == null ? '' : s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n');
    }
}