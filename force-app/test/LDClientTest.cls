@isTest
private class LDClientTest {
    private class RestMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String raw =
                '{"flags":' +
                    '{' +
                        '"hello": ' +
                        '{' +
                            '"version": 52, ' +
                            '"key": "hello", ' +
                            '"on": false, ' +
                            '"offVariation": 0, ' +
                            '"salt": "abc123", ' +
                            '"fallthrough": ' +
                            '{' +
                                '"variation": 0' +
                            '},' +
                            '"variations": [true]' +
                        '}' +
                    '}' +
                '}';

            HTTPResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'text/json');
            res.setBody(raw);
            res.setStatusCode(200);

            return res;
        }
    }

    @isTest static void basicVariation() {
        Test.setMock(HttpCalloutMock.class, new RestMock());

        LDConfig config = new LDConfig.Builder('sdk-xyz').build();
        LDUser   user   = new LDUser.Builder('user-key').build();
        LDClient client = new LDClient(config);

        Boolean result1 = client.boolVariation(user, 'hello', false);
        System.assertEquals(result1, true);

        Boolean result2 = client.boolVariation(user, 'fake', false);
        System.assertEquals(result2, false);
    }
}
