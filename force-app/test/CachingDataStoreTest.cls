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

  // LDClient sends a zero TTL to DataStore, but this class still supports it: a zero-length
  // cache is always expired, so each lookup reloads and then answers from what it loaded.
  @isTest
  static void zeroTtlReloadsOnEveryLookup() {
    CachingDataStore store = new CachingDataStore(0, new GetTimeMock());

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(CachingDataStoreTest.payload1));

    DataModel.Flag flag = store.getFlag('hello');
    System.assertEquals(flag.version, 52);

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(CachingDataStoreTest.payload2));

    flag = store.getFlag('hello');
    System.assertEquals(flag.version, 53);
  }

  // The reload has to leave the cache populated, not merely clear it. This is the shape of the
  // original defect: a zero TTL returned before loading, so every lookup answered null.
  @isTest
  static void zeroTtlStillServesEveryLookupKind() {
    CachingDataStore store = new CachingDataStore(0, new GetTimeMock());

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(CachingDataStoreTest.payload1));

    System.assertEquals(store.getFlag('hello').version, 52);
    System.assertEquals(store.getSegment('hello').version, 50);
    System.assertEquals(store.allFlags().size(), 1);
  }

  @isTest
  static void negativeTtlCachesIndefinitely() {
    GetTimeMock mockTime = new GetTimeMock();
    CachingDataStore store = new CachingDataStore(-1, mockTime);

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(CachingDataStoreTest.payload1));

    DataModel.Flag flag = store.getFlag('hello');
    System.assertEquals(flag.version, 52);

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(CachingDataStoreTest.payload2));

    flag = store.getFlag('hello');
    System.assertEquals(flag.version, 52);

    // Advance time far past any plausible TTL. A negative TTL never expires, so the store
    // still answers from the data it loaded first.
    mockTime.counter = 1000000;

    flag = store.getFlag('hello');
    System.assertEquals(flag.version, 52);
  }

  @isTest
  static void negativeTtlStillLoadsOnTheFirstLookup() {
    CachingDataStore store = new CachingDataStore(-1, new GetTimeMock());

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(CachingDataStoreTest.payload1));

    System.assertEquals(store.getFlag('hello').version, 52);
    System.assertEquals(store.getSegment('hello').version, 50);
    System.assertEquals(store.allFlags().size(), 1);
  }
}
