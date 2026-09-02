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

  // A table at the bound still drains in one call, so the bound costs nothing in normal
  // operation. The default queue cap is 1000 rows, which is five of these.
  @isTest
  static void aDrainAtTheBoundTakesEverything() {
    insertEvents(EventREST.MAX_EVENTS_PER_DRAIN, null);

    System.assertEquals(EventREST.MAX_EVENTS_PER_DRAIN, drainedCount(null));
    System.assertEquals(0, [SELECT COUNT() FROM EventData__c]);
  }

  // The case that matters. A table past a governor limit used to throw on every drain, so
  // nothing was deleted and the table could never shrink. It has to reduce on each call
  // instead, or an org that reached that state stays stuck there.
  @isTest
  static void aTableAboveTheBoundShrinksOnEveryDrain() {
    Integer bound = EventREST.MAX_EVENTS_PER_DRAIN;

    insertEvents(2 * bound + 1, null);

    System.assertEquals(bound, drainedCount(null));
    System.assertEquals(bound + 1, [SELECT COUNT() FROM EventData__c]);

    System.assertEquals(bound, drainedCount(null));
    System.assertEquals(1, [SELECT COUNT() FROM EventData__c]);

    System.assertEquals(1, drainedCount(null));
    System.assertEquals(0, [SELECT COUNT() FROM EventData__c]);
  }

  // The bound narrows the rows the scope filter runs over, so pin that the filter still
  // holds. A drain that reaches another scope delivers that scope's events to this bridge's
  // environment under this bridge's SDK key, and those events carry user attributes.
  @isTest
  static void aBoundedDrainTakesOnlyItsOwnScope() {
    insertEvents(EventREST.MAX_EVENTS_PER_DRAIN + 5, 'alpha');
    insertEvents(3, 'beta');

    EventREST.prepareEvents('alpha');
    EventREST.prepareEvents('alpha');

    System.assertEquals(0, [SELECT COUNT() FROM EventData__c WHERE Scope__c = 'alpha']);
    System.assertEquals(3, [SELECT COUNT() FROM EventData__c WHERE Scope__c = 'beta']);
  }

  // The fallback still delivers when the window is not full, which is the case it exists for.
  // A drain that deleted these rows without returning them would leave the case-mismatched
  // bridge posting nothing while its events were destroyed.
  @isTest
  static void aFallbackStillDeliversWhenTheWindowIsNotFull() {
    insertEvents(3, 'Alpha');

    System.assertEquals(3, drainedCount('alpha'));
    System.assertEquals(0, [SELECT COUNT() FROM EventData__c]);
  }

  // A full window of another casing must not reach the bundle. The drain still deletes it, so
  // the table shrinks, but delivering it would post that scope's events -- and the user
  // attributes they carry -- to this bridge's environment under this bridge's SDK key.
  //
  // Only the three 'alpha' rows may ever be delivered, whatever order the rows come back in.
  // A row of this scope is deleted only on a call that also delivers it, so the total is
  // exactly three. Before the window was bounded this returned all 203.
  @isTest
  static void aFullWindowOfAnotherCasingIsNotDelivered() {
    insertEvents(EventREST.MAX_EVENTS_PER_DRAIN, 'Alpha');
    insertEvents(3, 'alpha');

    Integer delivered = 0;
    Integer calls = 0;

    while ([SELECT COUNT() FROM EventData__c] > 0) {
      delivered += drainedCount('alpha');
      calls++;

      System.assert(delivered <= 3, 'the drain delivered ' + delivered + ' rows of one scope');
      System.assert(calls <= 4, 'the drain took more calls than the fixture needs');
    }

    System.assertEquals(3, delivered);
  }

  // The bound is applied by the query, and the query also matches a scope key that differs
  // from this one by letter case alone. A colliding key can therefore hold every slot in the
  // window while this scope still has rows waiting. No other scope can, because Salesforce
  // has already compared the keys without regard to case.
  //
  // Rows inserted in one transaction share a CreatedDate, so this test cannot fix which of
  // them lands in the window. Assert the property that holds under any order: every drain
  // deletes rows it read, so the table keeps shrinking and the drain never stalls. Each call
  // either takes at least one of this scope's rows, or finds none of them in the window and
  // deletes the whole window.
  //
  // Four calls therefore clear this fixture whatever the order. At most three of them take
  // one of the three 'alpha' rows, and the call after 'alpha' runs out takes the window.
  @isTest
  static void aBoundedDrainMakesProgressAgainstACollidingCasing() {
    insertEvents(EventREST.MAX_EVENTS_PER_DRAIN, 'Alpha');
    insertEvents(3, 'alpha');

    Integer remaining = [SELECT COUNT() FROM EventData__c];
    Integer calls = 0;

    while (remaining > 0) {
      EventREST.prepareEvents('alpha');

      Integer left = [SELECT COUNT() FROM EventData__c];

      System.assert(left < remaining, 'a drain removed nothing at ' + remaining + ' rows');

      remaining = left;
      calls++;

      System.assert(calls <= 4, 'the drain took more calls than the fixture needs');
    }
  }
}
