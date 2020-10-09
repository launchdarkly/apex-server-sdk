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

    @isTest static void allFlagsEmptyStore() {
        LDConfig config = new LDConfig.Builder('sdk-xyz').build();
        LDUser   user   = new LDUser.Builder('user-key').build();
        LDClient client = new LDClient(config);

        Map<String, LDValue> result = client.allFlags(user);
        System.assertEquals(result.size(), 0);
    }

    @isTest static void identify() {
        LDConfig config = new LDConfig.Builder('sdk-xyz').build();
        LDUser   user   = new LDUser.Builder('user-key').build();
        LDClient client = new LDClient(config);

        client.getTime = new GetTimeMock();

        client.identify(user);

        List<EventData__c> events = [select Kind__c, Raw__c from EventData__C];

        String expected = '{"creationDate":1,"user":{"key":"user-key"},"key":"user-key","kind":"identify"}';

        System.assertEquals(events.size(), 1);
        System.assertEquals(events.get(0).Kind__c, 'identify');
        System.assertEquals(events.get(0).Raw__c, expected);
    }

    @isTest static void trackMinimal() {
        LDConfig config = new LDConfig.Builder('sdk-xyz').build();
        LDUser   user   = new LDUser.Builder('user-key').build();
        LDClient client = new LDClient(config);
        
        client.getTime = new GetTimeMock();

        client.track(user, 'abc', null, null);

        List<EventData__c> events = [select Kind__c, Raw__c from EventData__C];

        String expected = '{"creationDate":1,"user":{"key":"user-key"},"key":"abc","kind":"custom"}';

        System.assertEquals(events.size(), 1);
        System.assertEquals(events.get(0).Kind__c, 'custom');
        System.assertEquals(events.get(0).Raw__c, expected);
    }

    @isTest static void trackFull() {
        LDConfig config = new LDConfig.Builder('sdk-xyz').build();
        LDUser   user   = new LDUser.Builder('user-key').build();
        LDClient client = new LDClient(config);
        LDValue  value  = new LDValueObject.Builder().set('a', LDValue.of(true)).build();
        
        client.getTime = new GetTimeMock();

        client.track(user, '123', (Double)52.1, value);

        List<EventData__c> events = [select Kind__c, Raw__c from EventData__C];

        String expected = '{"creationDate":1,"data":{"a":true},"metricValue":52.1,'
            + '"user":{"key":"user-key"},"key":"123","kind":"custom"}';

        System.assertEquals(events.size(), 1);
        System.assertEquals(events.get(0).Kind__c, 'custom');
        System.assertEquals(events.get(0).Raw__c, expected);
    }
}
