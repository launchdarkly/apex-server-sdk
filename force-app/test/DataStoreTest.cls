@isTest
private class DataStoreTest {
  private static final String flag1 = '{"version": 52, "key": "hello", "on": true, "salt": "salt", "variations": [true, false], "fallthrough": {"variation": 0}}';
  private static final String flag2 = '{"version": 53, "key": "hello", "on": true, "salt": "salt", "variations": [true, false], "fallthrough": {"variation": 0}}';

  private static final String segment1 = '{"version": 50, "key": "hello", "salt": "salt", "rules": []}';
  private static final String segment2 = '{"version": 51, "key": "hello", "salt": "salt", "rules": []}';

  private static final String payload1 =
    '{' +
    '"flags": {"hello": ' +
    flag1 +
    '},' +
    '"segments": {"hello": ' +
    segment1 +
    '}' +
    '}';

  @isTest
  static void invalidKeyReturnNullValue() {
    DataStore store = new DataStore();

    System.assertEquals(store.getFlag('bad_flag'), null);
    System.assertEquals(store.getSegment('bad_segment'), null);
  }

  @isTest
  static void putAllBasic() {
    DataStore store = new DataStore();

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(DataStoreTest.payload1));

    System.assertEquals(store.getVersioned('hello', 'flags').Raw__c, JSON.serialize(JSON.deserializeUntyped(flag1)));

    System.assertEquals(
      store.getVersioned('hello', 'segments').Raw__c,
      JSON.serialize(JSON.deserializeUntyped(segment1))
    );
  }

  @isTest
  static void putAllReplaces() {
    DataStore store = new DataStore();
    store.putAll((Map<String, Object>) JSON.deserializeUntyped(DataStoreTest.payload1));
    store.putAll((Map<String, Object>) JSON.deserializeUntyped('{}'));

    System.assertEquals(store.getFlag('hello'), null);
  }
}
