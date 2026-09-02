@isTest
private class EventRESTTest {
  @isTest
  static void basicBundle() {
    EventSink sink = new EventSink(1000);

    sink.sinkIdentify(new LDEvent.Identify(new LDUser.Builder('abc').build(), 0, false));
    sink.flush();

    Object bundle = EventREST.prepareEvents();

    Object bundleIso = JSON.deserializeUntyped(JSON.serialize(bundle));

    String expectedRaw = '[{"creationDate":0,"user":{"key":"abc"},"key":"abc","kind":"identify"}]';

    System.assertEquals(bundleIso, JSON.deserializeUntyped(expectedRaw));
  }

  @isTest
  static void restContext() {
    EventSink sink = new EventSink(1000);

    sink.sinkIdentify(new LDEvent.Identify(new LDUser.Builder('abc').build(), 0, false));
    sink.flush();

    RestResponse response = new RestResponse();

    RestContext.response = response;

    Test.startTest();

    EventREST.doGet();

    Test.stopTest();

    Blob bundle = RestContext.response.responseBody;

    Object bundleIso = JSON.deserializeUntyped(bundle.toString());

    String expectedRaw = '[{"creationDate":0,"user":{"key":"abc"},"key":"abc","kind":"identify"}]';

    System.assertEquals(bundleIso, (Object) JSON.deserializeUntyped(expectedRaw), bundleIso);
  }

  // One statement, because the fixture and the drain share one transaction's limit of 150
  // DML statements. A row at a time exhausts that before the drain runs.
  private static void insertEvents(Integer count, String scope) {
    List<EventData__c> rows = new List<EventData__c>();

    for (Integer i = 0; i < count; i++) {
      rows.add(new EventData__c(Kind__c = 'identify', Raw__c = '{}', Scope__c = scope));
    }

    insert rows;
  }

  // An identify event passes through the processor untouched and no summary is built for it,
  // so the bundle holds exactly one entry per row the drain took.
  private static Integer drainedCount(String scope) {
    return ((List<Object>) EventREST.prepareEvents(scope)).size();
  }

  // A table at the bound drains in one call. The bound sits above the default queue cap of
  // 1000, so the supported default configuration never leaves rows behind for the next poll.
  @isTest
  static void aDrainAtTheBoundTakesEverything() {
    insertEvents(EventREST.MAX_EVENTS_PER_DRAIN, null);

    // The fixture's own heap and DML use is charged to the test rather than to the drain.
    // Reset the limits so each drain runs against the budget it gets in production.
    Test.startTest();

    System.assertEquals(EventREST.MAX_EVENTS_PER_DRAIN, drainedCount(null));

    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM EventData__c]);
  }

  // The case that matters. A table past a governor limit used to throw on every drain, so
  // nothing was deleted and the table could never shrink. It has to reduce on each call
  // instead, or an org that reached that state stays stuck there.
  @isTest
  static void aTableAboveTheBoundShrinksOnEveryDrain() {
    Integer bound = EventREST.MAX_EVENTS_PER_DRAIN;

    // One row over the bound. The fixture and the two drains share one transaction's limit of
    // 10,000 DML rows, and a larger backlog proves nothing more.
    insertEvents(bound + 1, null);

    // The fixture's own heap and DML use is charged to the test rather than to the drain.
    // Reset the limits so each drain runs against the budget it gets in production.
    Test.startTest();

    System.assertEquals(bound, drainedCount(null));
    System.assertEquals(1, [SELECT COUNT() FROM EventData__c]);

    System.assertEquals(1, drainedCount(null));
    System.assertEquals(0, [SELECT COUNT() FROM EventData__c]);

    Test.stopTest();
  }

  // The bound narrows the rows the scope filter runs over, so pin that the filter still
  // holds. A drain that reaches another scope delivers that scope's events to this bridge's
  // environment under this bridge's SDK key, and those events carry user attributes.
  @isTest
  static void aBoundedDrainTakesOnlyItsOwnScope() {
    insertEvents(EventREST.MAX_EVENTS_PER_DRAIN + 5, 'alpha');
    insertEvents(3, 'beta');

    // The fixture's own heap and DML use is charged to the test rather than to the drain.
    // Reset the limits so each drain runs against the budget it gets in production.
    Test.startTest();

    EventREST.prepareEvents('alpha');
    EventREST.prepareEvents('alpha');

    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM EventData__c WHERE Scope__c = 'alpha']);
    System.assertEquals(3, [SELECT COUNT() FROM EventData__c WHERE Scope__c = 'beta']);
  }

  // A colliding casing is never delivered and never deleted, however many rows it holds and
  // whether or not the window is full. Delivering it would post that scope's events, and the
  // user attributes they carry, to this bridge's environment under this bridge's SDK key.
  //
  // The window holds every row here, so no ordering can hide one. Repeating the drain pins
  // that the colliding rows are not taken on a later call either.
  @isTest
  static void aCollidingCasingIsNeitherDeliveredNorDeleted() {
    insertEvents(3, 'Alpha');
    insertEvents(2, 'alpha');

    System.assertEquals(2, drainedCount('alpha'));
    System.assertEquals(3, [SELECT COUNT() FROM EventData__c]);

    System.assertEquals(0, drainedCount('alpha'));
    System.assertEquals(3, [SELECT COUNT() FROM EventData__c]);
  }
}
