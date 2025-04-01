@isTest
private class CachingDataStoreTest {
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

  private static final String payload2 =
    '{' +
    '"flags": {"hello": ' +
    flag2 +
    '},' +
    '"segments": {"hello": ' +
    segment2 +
    '}' +
    '}';

  @isTest
  static void invalidKeyReturnNullValue() {
    CachingDataStore store = new CachingDataStore(10, new GetTimeMock());

    System.assertEquals(store.getFlag('bad_flag'), null);
    System.assertEquals(store.getSegment('bad_segment'), null);
  }

  @isTest
  static void putAllBasic() {
    CachingDataStore store = new CachingDataStore(10, new GetTimeMock());

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(CachingDataStoreTest.payload1));

    System.assertEquals(store.getVersioned('hello', 'flags').Raw__c, JSON.serialize(JSON.deserializeUntyped(flag1)));

    System.assertEquals(
      store.getVersioned('hello', 'segments').Raw__c,
      JSON.serialize(JSON.deserializeUntyped(segment1))
    );
  }

  @isTest
  static void putAllDoesNotInvalidateCache() {
    CachingDataStore store = new CachingDataStore(10, new GetTimeMock());

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(CachingDataStoreTest.payload1));

    DataModel.Flag flag = store.getFlag('hello');
    System.assertEquals(flag.version, 52);

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(CachingDataStoreTest.payload2));

    flag = store.getFlag('hello');
    System.assertEquals(flag.version, 52);
  }

  @isTest
  static void cacheInvalidatesAfterPeriodOfTime() {
    GetTimeMock mockTime = new GetTimeMock();
    CachingDataStore store = new CachingDataStore(10, mockTime);

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(CachingDataStoreTest.payload1));

    DataModel.Flag flag = store.getFlag('hello');
    System.assertEquals(flag.version, 52);

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(CachingDataStoreTest.payload2));
    flag = store.getFlag('hello');
    System.assertEquals(flag.version, 52);

    // Advance time
    mockTime.counter = 10;

    flag = store.getFlag('hello');
    System.assertEquals(flag.version, 53);
  }

  @isTest
  static void negativeCacheIsAlwaysExpired() {
    CachingDataStore store = new CachingDataStore(-1, new GetTimeMock());

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(CachingDataStoreTest.payload1));

    DataModel.Flag flag = store.getFlag('hello');
    System.assertEquals(flag.version, 52);

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(CachingDataStoreTest.payload2));

    flag = store.getFlag('hello');
    System.assertEquals(flag.version, 53);
  }
}
