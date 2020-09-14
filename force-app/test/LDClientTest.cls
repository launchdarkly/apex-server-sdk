@isTest
private class LDClientTest {
    @isTest static void basicVariation() {
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

        DataStore store = new DataStore();
        store.putAll((Map<String, Object>)JSON.deserializeUntyped(raw));

        LDConfig config = new LDConfig.Builder('sdk-xyz').build();
        LDUser   user   = new LDUser.Builder('user-key').build();
        LDClient client = new LDClient(config);

        Boolean result1 = client.boolVariation(user, 'hello', false);
        System.assertEquals(result1, true);

        Boolean result2 = client.boolVariation(user, 'fake', false);
        System.assertEquals(result2, false);
    }
}
