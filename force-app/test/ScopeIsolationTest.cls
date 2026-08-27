// Pins the invariant that one scope's data is never visible to, drained by, or deleted by
// another's.
//
// This exists as one behavioural suite rather than as assertions bolted onto each store and
// sink test on purpose. Scoping is applied at a dozen separate query sites, and a single
// missed filter is a silent correctness bug -- during implementation one site was already
// missed by a careful manual grep, because CachingDataStore spells the type VersionedData__C
// with a capital C. Tests that assert the observable property catch a missed filter at any
// site, including sites that do not exist yet.
//
// Every fixture below deliberately uses the SAME flag and segment keys in both scopes.
// Keys are not unique across LaunchDarkly projects, so colliding keys are the normal case,
// and getVersioned ends in LIMIT 1 -- an unscoped lookup returns an arbitrary scope's row.
@isTest
private class ScopeIsolationTest {
  private static final String ALPHA = 'alpha';
  private static final String BETA = 'beta';

  // Same key, different version, so the version identifies which scope a row came from.
  //
  // The flag is spelled out in full rather than as just a key and version. A minimal object
  // round-trips through getVersioned but throws inside DataModel.Flag, which allFlags swallows
  // and getFlag propagates -- so an under-specified fixture reads as a scoping failure.
  private static String flagPayload(Integer version) {
    return '{"flags":{"shared":{"version":' + version + ',"key":"shared","on":false,' +
      '"variations":[true],"offVariation":0,"fallthrough":{"variation":0},' +
      '"prerequisites":[],"targets":[],"rules":[],"salt":"s"}},"segments":{}}';
  }

  private static String segmentPayload(Integer version) {
    return '{"flags":{},"segments":{"shared":{"version":' + version + ',"key":"shared"}}}';
  }

  private static Map<String, Object> parse(String payload) {
    return (Map<String, Object>) JSON.deserializeUntyped(payload);
  }

  @isTest
  static void flagsAreIsolatedByScope() {
    new DataStore(ALPHA).putAll(parse(flagPayload(1)));
    new DataStore(BETA).putAll(parse(flagPayload(2)));

    System.assertEquals(1, new DataStore(ALPHA).getVersioned('shared', 'flags').Version__c);
    System.assertEquals(2, new DataStore(BETA).getVersioned('shared', 'flags').Version__c);

    System.assertEquals(1, new DataStore(ALPHA).allFlags().size());
    System.assertEquals(1, new DataStore(BETA).allFlags().size());
  }

  @isTest
  static void putAllOnlyDeletesItsOwnScope() {
    new DataStore(ALPHA).putAll(parse(flagPayload(1)));
    new DataStore(BETA).putAll(parse(flagPayload(2)));

    // An unscoped delete here is the failure that makes two bridges destroy each other's
    // flag data on every push.
    new DataStore(ALPHA).putAll(parse('{}'));

    System.assertEquals(null, new DataStore(ALPHA).getFlag('shared'));
    System.assertNotEquals(null, new DataStore(BETA).getFlag('shared'));
  }

  @isTest
  static void legacyNullScopeIsIsolated() {
    // What an org looks like before scoping support, and what a bridge without a
    // scope key keeps writing during a migration.
    new DataStore().putAll(parse(flagPayload(9)));
    new DataStore(ALPHA).putAll(parse(flagPayload(1)));

    System.assertEquals(9, new DataStore().getVersioned('shared', 'flags').Version__c);
    System.assertEquals(1, new DataStore(ALPHA).getVersioned('shared', 'flags').Version__c);

    // The named scope's push must not disturb the legacy rows still serving old clients.
    new DataStore(ALPHA).putAll(parse('{}'));
    System.assertNotEquals(null, new DataStore().getFlag('shared'));
  }

  @isTest
  static void cachingStoreIsolatesByScope() {
    new DataStore(ALPHA).putAll(parse(flagPayload(1)));
    new DataStore(BETA).putAll(parse(flagPayload(2)));

    CachingDataStore alphaStore = new CachingDataStore(60000, new GetTimeMock(), ALPHA);
    CachingDataStore betaStore = new CachingDataStore(60000, new GetTimeMock(), BETA);

    System.assertEquals(1, alphaStore.allFlags().size());
    System.assertEquals(1, betaStore.allFlags().size());
    System.assertEquals(1, alphaStore.getVersioned('shared', 'flags').Version__c);
    System.assertEquals(2, betaStore.getVersioned('shared', 'flags').Version__c);
  }

  @isTest
  static void cachingStorePutAllOnlyDeletesItsOwnScope() {
    new CachingDataStore(60000, new GetTimeMock(), ALPHA).putAll(parse(flagPayload(1)));
    new CachingDataStore(60000, new GetTimeMock(), BETA).putAll(parse(flagPayload(2)));

    new CachingDataStore(60000, new GetTimeMock(), ALPHA).putAll(parse('{}'));

    System.assertEquals(null, new DataStore(ALPHA).getFlag('shared'));
    System.assertNotEquals(null, new DataStore(BETA).getFlag('shared'));
  }

  @isTest
  static void segmentsAreIsolatedByScope() {
    new DataStore(ALPHA).putAll(parse(segmentPayload(1)));
    new DataStore(BETA).putAll(parse(segmentPayload(2)));

    System.assertEquals(1, new DataStore(ALPHA).getVersioned('shared', 'segments').Version__c);
    System.assertEquals(2, new DataStore(BETA).getVersioned('shared', 'segments').Version__c);
  }

  // The subtlest case, and the reason the scope is bound to the store rather than passed
  // per call: Evaluator resolves prerequisites by key alone. A leak here does not produce
  // missing data, it produces a confidently wrong answer.
  //
  // Both scopes hold an identical 'gated' flag whose prerequisite is 'prereq'. Alpha's
  // prereq is on and serves the required variation, so 'gated' falls through to true.
  // Beta's prereq is off, which fails the prerequisite regardless of variation, so 'gated'
  // returns its off variation, false.
  private static final String GATED =
    '{"version":1,"key":"gated","on":true,"variations":[false,true],' +
    '"offVariation":0,"fallthrough":{"variation":1},' +
    '"prerequisites":[{"key":"prereq","variation":0}],"targets":[],"rules":[],"salt":"s"}';

  private static String prereqFlag(Boolean prereqIsOn) {
    return '{"version":1,"key":"prereq","on":' + (prereqIsOn ? 'true' : 'false') +
      ',"variations":[true],"offVariation":0,"fallthrough":{"variation":0},' +
      '"prerequisites":[],"targets":[],"rules":[],"salt":"s"}';
  }

  private static String gatedPayload(Boolean prereqIsOn) {
    return '{"flags":{"gated":' + GATED + ',"prereq":' + prereqFlag(prereqIsOn) + '},"segments":{}}';
  }

  @isTest
  static void prerequisiteResolvesWithinScope() {
    new DataStore(ALPHA).putAll(parse(gatedPayload(true)));
    new DataStore(BETA).putAll(parse(gatedPayload(false)));

    LDUser user = new LDUser.Builder('user-key').build();

    LDClient alphaClient = new LDClient(new LDConfig.Builder().setScopeKey(ALPHA).build());
    LDClient betaClient = new LDClient(new LDConfig.Builder().setScopeKey(BETA).build());

    System.assertEquals(true, alphaClient.boolVariation(user, 'gated', false));
    System.assertEquals(false, betaClient.boolVariation(user, 'gated', true));
  }

  @isTest
  static void eventDrainIsolatesByScope() {
    insert new List<EventData__c>{
      new EventData__c(Kind__c = 'identify', Raw__c = '{}', Scope__c = ALPHA),
      new EventData__c(Kind__c = 'identify', Raw__c = '{}', Scope__c = BETA),
      new EventData__c(Kind__c = 'identify', Raw__c = '{}', Scope__c = null)
    };

    // An unscoped drain delivers another scope's events to this bridge's environment
    // under this bridge's SDK key, and those events carry user attributes.
    EventREST.prepareEvents(ALPHA);

    System.assertEquals(0, [SELECT COUNT() FROM EventData__c WHERE Scope__c = :ALPHA]);
    System.assertEquals(1, [SELECT COUNT() FROM EventData__c WHERE Scope__c = :BETA]);
    System.assertEquals(1, [SELECT COUNT() FROM EventData__c WHERE Scope__c = null]);
  }

  @isTest
  static void eventQueueCapIsPerScope() {
    EventSink alphaSink = new EventSink(2, ALPHA);
    alphaSink.sinkGeneric('identify', '{}');
    alphaSink.sinkGeneric('identify', '{}');
    alphaSink.sinkGeneric('identify', '{}');

    System.assertEquals(2, [SELECT COUNT() FROM EventData__c WHERE Scope__c = :ALPHA]);

    // Alpha being at its cap must not stop beta recording. With an unscoped count, another
    // scope's undrained events silently stop this one from recording anything at all.
    EventSink betaSink = new EventSink(2, BETA);
    betaSink.sinkGeneric('identify', '{}');

    System.assertEquals(1, [SELECT COUNT() FROM EventData__c WHERE Scope__c = :BETA]);
  }

  @isTest
  static void batchingSinkStampsScope() {
    BatchingEventSink sink = new BatchingEventSink(10, ALPHA);
    sink.sinkGeneric('identify', '{}');
    sink.close();

    System.assertEquals(1, [SELECT COUNT() FROM EventData__c WHERE Scope__c = :ALPHA]);
  }

  @isTest
  static void headerReadIsCaseInsensitiveAndTreatsBlankAsUnset() {
    RestRequest request = new RestRequest();
    request.headers.put('ld-scope-key', ALPHA);
    System.assertEquals(ALPHA, ScopeHeader.read(request, EventREST.SCOPE_HEADER));

    RestRequest blank = new RestRequest();
    blank.headers.put(EventREST.SCOPE_HEADER, '   ');
    System.assertEquals(null, ScopeHeader.read(blank, EventREST.SCOPE_HEADER));

    System.assertEquals(null, ScopeHeader.read(new RestRequest(), EventREST.SCOPE_HEADER));
  }
}
