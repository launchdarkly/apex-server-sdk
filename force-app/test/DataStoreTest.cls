@isTest
private class DataStoreTest {
    private static final String payload1 =
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

    @isTest static void invalidKeyReturnNullValue() {
        DataStore store = new DataStore();

        System.assertEquals(store.getFlag('bad_flag'), null);
        System.assertEquals(store.getSegment('bad_segment'), null);
    }

    @isTest static void putAllBasic() {
        DataStore store = new DataStore();
        store.putAll((Map<String, Object>)JSON.deserializeUntyped(DataStoreTest.payload1));

        System.assertNotEquals(store.getFlag('hello'), null);
    }

    @isTest static void putAllReplaces() {
        DataStore store = new DataStore();
        store.putAll((Map<String, Object>)JSON.deserializeUntyped(DataStoreTest.payload1));
        store.putAll((Map<String, Object>)JSON.deserializeUntyped('{}'));

        System.assertEquals(store.getFlag('hello'), null);
    }
}
