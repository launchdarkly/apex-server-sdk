// Pins the one thing this SDK guarantees about scope keys that differ only by letter case:
// an unsupported key never destroys a supported scope's data.
//
// Salesforce matches text without regard to case, so a filter for scope 'alpha' also returns
// the records of scope 'Alpha'. Reads are deliberately left alone -- which record an
// unsupported key resolves to is undefined. Deleting and draining are not, because they remove
// data, and a typo in one bridge's scope key must not wipe out another scope.
@isTest
private class ScopeCaseTest {
  private static Map<String, Object> flagPayload(Integer version) {
    return (Map<String, Object>) JSON.deserializeUntyped(
      '{"flags":{"shared":{"version":' + version + ',"key":"shared","on":false,' +
        '"variations":[true],"offVariation":0,"fallthrough":{"variation":0},' +
        '"prerequisites":[],"targets":[],"rules":[],"salt":"s"}},"segments":{}}'
    );
  }

  // A push for 'alpha' must leave 'Alpha' alone, in both stores.
  @isTest
  static void aPushDoesNotDeleteACollidingScope() {
    new DataStore('Alpha').putAll(flagPayload(1));
    new DataStore('alpha').putAll(flagPayload(2));

    System.assertEquals(2, [SELECT COUNT() FROM VersionedData__c]);
  }

  @isTest
  static void aCachedPushDoesNotDeleteACollidingScope() {
    new CachingDataStore(30000, new GetTimeImpl(), 'Alpha').putAll(flagPayload(1));
    new CachingDataStore(30000, new GetTimeImpl(), 'alpha').putAll(flagPayload(2));

    System.assertEquals(2, [SELECT COUNT() FROM VersionedData__c]);
  }

  // The first push of a new scope finds no records of its own. It must still not fall back to
  // deleting the records of the scope whose key differs only by case.
  @isTest
  static void aFirstPushDoesNotDeleteACollidingScope() {
    new DataStore('Alpha').putAll(flagPayload(1));

    System.assertEquals(1, [SELECT COUNT() FROM VersionedData__c]);

    new DataStore('alpha').putAll(flagPayload(2));

    System.assertEquals(1, [SELECT COUNT() FROM VersionedData__c WHERE Scope__c = 'Alpha' AND Version__c = 1]);
  }

  // A push must still replace its own scope's records, which is the behavior the guard has to
  // preserve.
  @isTest
  static void aPushStillReplacesItsOwnRecords() {
    new DataStore('Alpha').putAll(flagPayload(1));
    new DataStore('Alpha').putAll(flagPayload(2));

    System.assertEquals(1, [SELECT COUNT() FROM VersionedData__c]);
    System.assertEquals(2, new DataStore('Alpha').getVersioned('shared', 'flags').Version__c);
  }

  // Records that carry no scope are their own scope, and a push for a named scope must not
  // delete them. This is the state an org is in before it configures a scope at all.
  @isTest
  static void aPushDoesNotDeleteRecordsWithNoScope() {
    new DataStore(null).putAll(flagPayload(1));
    new DataStore('Alpha').putAll(flagPayload(2));

    System.assertEquals(2, [SELECT COUNT() FROM VersionedData__c]);
    System.assertEquals(1, new DataStore(null).getVersioned('shared', 'flags').Version__c);
  }

  // When both casings have events of their own, each bridge drains only its own.
  @isTest
  static void aDrainDoesNotTakeACollidingScopesEvents() {
    new EventSink(1000, 'Alpha').sinkGeneric('custom', '{}');
    new EventSink(1000, 'alpha').sinkGeneric('custom', '{}');

    EventREST.prepareEvents('Alpha');

    List<EventData__c> left = [SELECT Scope__c FROM EventData__c];
    System.assertEquals(1, left.size());
    System.assertEquals('alpha', left.get(0).Scope__c);
  }

  // A bridge whose scope key differs in case from the Apex client's still drains, because
  // nothing else drains those events. Refer to CaseMatch.eventsForScope.
  @isTest
  static void aDrainFallsBackWhenNoEventsMatchExactly() {
    new EventSink(1000, 'Alpha').sinkGeneric('custom', '{}');

    EventREST.prepareEvents('alpha');

    System.assertEquals(0, [SELECT COUNT() FROM EventData__c]);
  }

  @isTest
  static void aNullScopeIsDistinctFromANamedOne() {
    System.assertEquals(true, CaseMatch.sameScope(null, null));
    System.assertEquals(false, CaseMatch.sameScope(null, 'alpha'));
    System.assertEquals(false, CaseMatch.sameScope('alpha', null));
    System.assertEquals(true, CaseMatch.sameScope('alpha', 'alpha'));
    System.assertEquals(false, CaseMatch.sameScope('Alpha', 'alpha'));
  }
}
