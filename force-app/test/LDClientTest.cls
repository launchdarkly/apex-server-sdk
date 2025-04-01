@isTest
private class LDClientTest {
  static string rawStringBuilder(Object obj) {
    return '{"flags":' +
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
      '"variations": [' +
      obj +
      ']' +
      '}' +
      '}' +
      '}';
  }

  @isTest
  static void basicVariation() {
    DataStore store = new DataStore();
    store.putAll((Map<String, Object>) JSON.deserializeUntyped(LDClientTest.rawStringBuilder(true)));

    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);

    Boolean result1 = client.boolVariation(user, 'hello', false);
    System.assertEquals(result1, true);

    Boolean result2 = client.boolVariation(user, 'fake', false);
    System.assertEquals(result2, false);
  }

  @isTest
  static void canEvaluateMoreThan100TimesWithCaching() {
    DataStore store = new DataStore();
    store.putAll((Map<String, Object>) JSON.deserializeUntyped(LDClientTest.rawStringBuilder(true)));

    LDConfig config = new LDConfig.Builder().setCacheTtl(100).setBatchEvents(true).build();
    LDClient client = new LDClient(config);

    for (Integer i = 0, j = 0; i < 200; i++) {
      LDUser user = new LDUser.Builder('user-key').setName('Sandy').setKey('Test-' + i).build();
      Boolean value = client.boolVariation(user, 'hello', false);
      System.assertEquals(true, value);
    }

    client.close();
  }

  @isTest
  static void basicVariationWithDetail() {
    DataStore store = new DataStore();
    store.putAll((Map<String, Object>) JSON.deserializeUntyped(LDClientTest.rawStringBuilder(true)));

    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);
    LDClient.EvaluationDetail detail = new LDClient.EvaluationDetail();

    Boolean result1 = client.boolVariation(user, 'hello', false, detail);

    System.assertEquals(result1, true);
    System.assertEquals(detail.getReason().getKind(), EvaluationReason.Kind.OFF);
    System.assertEquals(detail.getVariationIndex(), 0);
  }

  @isTest
  static void intVariation() {
    DataStore store = new DataStore();
    store.putAll((Map<String, Object>) JSON.deserializeUntyped(LDClientTest.rawStringBuilder(1)));

    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);

    Integer result1 = client.intVariation(user, 'hello', 0);

    System.assertEquals(result1, 1);
  }

  @isTest
  static void intVariationWithDetail() {
    DataStore store = new DataStore();
    store.putAll((Map<String, Object>) JSON.deserializeUntyped(LDClientTest.rawStringBuilder(1)));

    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);
    LDClient.EvaluationDetail detail = new LDClient.EvaluationDetail();

    Integer result1 = client.intVariation(user, 'hello', 0, detail);

    System.assertEquals(result1, 1);
    System.assertEquals(detail.getReason().getKind(), EvaluationReason.Kind.OFF);
  }

  @isTest
  static void doubleVariation() {
    DataStore store = new DataStore();
    store.putAll((Map<String, Object>) JSON.deserializeUntyped(LDClientTest.rawStringBuilder(1)));

    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);

    Double result1 = client.doubleVariation(user, 'hello', 0);

    System.assertEquals(result1, 1);
  }

  @isTest
  static void doubleVariationWithDetail() {
    DataStore store = new DataStore();
    store.putAll((Map<String, Object>) JSON.deserializeUntyped(LDClientTest.rawStringBuilder(1)));

    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);
    LDClient.EvaluationDetail detail = new LDClient.EvaluationDetail();

    Double result1 = client.doubleVariation(user, 'hello', 0, detail);

    System.assertEquals(result1, 1);
    System.assertEquals(detail.getReason().getKind(), EvaluationReason.Kind.OFF);
  }

  @isTest
  static void stringVariation() {
    DataStore store = new DataStore();
    store.putAll((Map<String, Object>) JSON.deserializeUntyped(LDClientTest.rawStringBuilder('"' + 1 + '"')));

    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);

    String result1 = client.stringVariation(user, 'hello', '1');

    System.assertEquals(result1, '1');
  }

  @isTest
  static void stringVariationWithDetail() {
    DataStore store = new DataStore();
    store.putAll((Map<String, Object>) JSON.deserializeUntyped(LDClientTest.rawStringBuilder('"' + 1 + '"')));

    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);
    LDClient.EvaluationDetail detail = new LDClient.EvaluationDetail();

    String result1 = client.stringVariation(user, 'hello', '0', detail);

    System.assertEquals(result1, '1');
    System.assertEquals(detail.getReason().getKind(), EvaluationReason.Kind.OFF);
  }

  @isTest
  static void jsonVariation() {
    Integer x = 7;
    LDValue value = LDValue.of(x);

    DataStore store = new DataStore();
    store.putAll((Map<String, Object>) JSON.deserializeUntyped(LDClientTest.rawStringBuilder(JSOn.serialize(value))));

    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);
    LDValue result1 = client.jsonVariation(user, 'hello', value);

    System.assertEquals(result1.intValue(), 0);
  }

  @isTest
  static void jsonVariationWithDetail() {
    Integer x = 7;
    LDValue value = LDValue.of(x);

    DataStore store = new DataStore();
    store.putAll((Map<String, Object>) JSON.deserializeUntyped(LDClientTest.rawStringBuilder(JSOn.serialize(value))));

    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);
    LDClient.EvaluationDetail detail = new LDClient.EvaluationDetail();

    LDValue result1 = client.jsonVariation(user, 'hello', value, detail);

    System.assertEquals(result1.intValue(), 0);
    System.assertEquals(detail.getReason().getKind(), EvaluationReason.Kind.OFF);
  }

  @isTest
  static void allFlagsEmptyStore() {
    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);

    Map<String, LDValue> result = client.allFlags(user);
    System.assertEquals(result.size(), 0);
  }

  @isTest
  static void identify() {
    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);

    client.getTime = new GetTimeMock();

    client.identify(user);
    client.close();

    List<EventData__c> events = [SELECT Kind__c, Raw__c FROM EventData__C];

    String expected = '{"creationDate":1,"user":{"key":"user-key"},"key":"user-key","kind":"identify"}';

    System.assertEquals(events.size(), 1);
    System.assertEquals(events.get(0).Kind__c, 'identify');
    System.assertEquals(events.get(0).Raw__c, expected);
  }

  @isTest
  static void alias() {
    LDConfig config = new LDConfig.Builder().build();
    LDUser currentUser = new LDUser.Builder('a').build();
    LDUser previousUser = new LDUser.Builder('b').build();
    LDClient client = new LDClient(config);

    client.getTime = new GetTimeMock();

    client.alias(currentUser, previousUser);
    client.close();

    List<EventData__c> events = [SELECT Kind__c, Raw__c FROM EventData__C];

    String expected =
      '{' +
      '"creationDate":1,' +
      '"key":"a",' +
      '"contextKind": "user",' +
      '"previousKey":"b",' +
      '"previousContextKind": "user",' +
      '"kind":"alias"' +
      '}';

    System.assertEquals(events.size(), 1);
    System.assertEquals(events.get(0).Kind__c, 'alias');
    System.assertEquals(JSON.deserializeUntyped(events.get(0).Raw__c), JSON.deserializeUntyped(expected));
  }

  @isTest
  static void trackMinimal() {
    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);

    client.getTime = new GetTimeMock();

    client.track(user, 'abc', null, null);
    client.close();

    List<EventData__c> events = [SELECT Kind__c, Raw__c FROM EventData__C];

    String expected = '{"creationDate":1,"user":{"key":"user-key"},"key":"abc","kind":"custom"}';

    System.assertEquals(events.size(), 1);
    System.assertEquals(events.get(0).Kind__c, 'custom');
    System.assertEquals(events.get(0).Raw__c, expected);
  }

  @isTest
  static void trackFull() {
    LDConfig config = new LDConfig.Builder().build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);
    LDValue value = new LDValueObject.Builder().set('a', LDValue.of(true)).build();

    client.getTime = new GetTimeMock();

    client.track(user, '123', (Double) 52.1, value);
    client.close();

    List<EventData__c> events = [SELECT Kind__c, Raw__c FROM EventData__C];

    String expected =
      '{"creationDate":1,"data":{"a":true},"metricValue":52.1,' +
      '"user":{"key":"user-key"},"key":"123","kind":"custom"}';

    System.assertEquals(events.size(), 1);
    System.assertEquals(events.get(0).Kind__c, 'custom');
    System.assertEquals(events.get(0).Raw__c, expected);
  }
}
