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
  private static Integer drainedCount(String scope, Integer maxEvents) {
    return ((List<Object>) EventREST.prepareEvents(scope, maxEvents)).size();
  }

  // A drain limit arrives as a query parameter, so the tests that resolve one need a request
  // to read it from. A null value stands for a caller that names no limit.
  private static RestRequest requestWithMaxEvents(String raw) {
    RestRequest request = new RestRequest();

    if (raw != null) {
      request.params.put(EventREST.MAX_EVENTS_PARAM, raw);
    }

    return request;
  }

  // A caller that names no limit gets the default. A bridge that predates the parameter sends
  // nothing, and it has to keep draining.
  @isTest
  static void anAbsentLimitUsesTheDefault() {
    System.assertEquals(EventREST.MAX_EVENTS_PER_DRAIN, EventREST.resolveMaxEvents(null));
    System.assertEquals(
      EventREST.MAX_EVENTS_PER_DRAIN,
      EventREST.resolveMaxEvents(requestWithMaxEvents(null))
    );
    System.assertEquals(
      EventREST.MAX_EVENTS_PER_DRAIN,
      EventREST.resolveMaxEvents(requestWithMaxEvents(''))
    );
    System.assertEquals(
      EventREST.MAX_EVENTS_PER_DRAIN,
      EventREST.resolveMaxEvents(requestWithMaxEvents('   '))
    );
  }

  @isTest
  static void aLimitInRangeIsHonored() {
    System.assertEquals(250, EventREST.resolveMaxEvents(requestWithMaxEvents('250')));
    System.assertEquals(250, EventREST.resolveMaxEvents(requestWithMaxEvents('  250  ')));
    System.assertEquals(1, EventREST.resolveMaxEvents(requestWithMaxEvents('1')));
    System.assertEquals(
      EventREST.MAX_EVENTS_PER_DRAIN,
      EventREST.resolveMaxEvents(
        requestWithMaxEvents(String.valueOf(EventREST.MAX_EVENTS_PER_DRAIN))
      )
    );
  }

  // A caller that asks for more rows than one transaction can delete still drains, at the
  // most rows the platform allows. This is the only way to pin the ceiling: no fixture can
  // insert more rows than it, because the fixture and the drain share one DML row limit.
  @isTest
  static void aLimitAboveTheCeilingIsLowered() {
    System.assertEquals(
      EventREST.MAX_EVENTS_PER_DRAIN,
      EventREST.resolveMaxEvents(
        requestWithMaxEvents(String.valueOf(EventREST.MAX_EVENTS_PER_DRAIN + 1))
      )
    );
    System.assertEquals(
      EventREST.MAX_EVENTS_PER_DRAIN,
      EventREST.resolveMaxEvents(requestWithMaxEvents('50000'))
    );
  }

  // Present and unusable, so the endpoint refuses rather than substituting the default. A
  // caller names a lower limit to stay under a limit this SDK cannot measure for it, and
  // draining at the default instead would throw in the way the caller asked to avoid.
  @isTest
  static void aLimitThatIsNotAPositiveIntegerIsRefused() {
    System.assertEquals(null, EventREST.resolveMaxEvents(requestWithMaxEvents('0')));
    System.assertEquals(null, EventREST.resolveMaxEvents(requestWithMaxEvents('-1')));
    System.assertEquals(null, EventREST.resolveMaxEvents(requestWithMaxEvents('many')));
    System.assertEquals(null, EventREST.resolveMaxEvents(requestWithMaxEvents('250.5')));

    // Too large to hold in an Integer. Integer.valueOf throws on this as it does on text,
    // so both arrive as the same bad request.
    System.assertEquals(null, EventREST.resolveMaxEvents(requestWithMaxEvents('99999999999')));
  }

  // A table at the limit drains in one call.
  @isTest
  static void aDrainAtTheLimitTakesEverything() {
    insertEvents(5, null);

    // The fixture's own heap and DML use is charged to the test rather than to the drain.
    // Reset the limits so each drain runs against the budget it gets in production.
    Test.startTest();

    System.assertEquals(5, drainedCount(null, 5));

    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM EventData__c]);
  }

  // The case that matters. A table past a governor limit used to throw on every drain, so
  // nothing was deleted and the table could never shrink. It has to reduce on each call
  // instead, or an org that reached that state stays stuck there.
  @isTest
  static void aTableAboveTheLimitShrinksOnEveryDrain() {
    insertEvents(5, null);

    // The fixture's own heap and DML use is charged to the test rather than to the drain.
    // Reset the limits so each drain runs against the budget it gets in production.
    Test.startTest();

    System.assertEquals(2, drainedCount(null, 2));
    System.assertEquals(3, [SELECT COUNT() FROM EventData__c]);

    System.assertEquals(2, drainedCount(null, 2));
    System.assertEquals(1, [SELECT COUNT() FROM EventData__c]);

    System.assertEquals(1, drainedCount(null, 2));
    System.assertEquals(0, [SELECT COUNT() FROM EventData__c]);

    Test.stopTest();
  }

  // The limit narrows the rows the scope filter runs over, so pin that the filter still
  // holds. A drain that reaches another scope delivers that scope's events to this bridge's
  // environment under this bridge's SDK key, and those events carry user attributes.
  @isTest
  static void aBoundedDrainTakesOnlyItsOwnScope() {
    insertEvents(5, 'alpha');
    insertEvents(3, 'beta');

    // The fixture's own heap and DML use is charged to the test rather than to the drain.
    // Reset the limits so each drain runs against the budget it gets in production.
    Test.startTest();

    EventREST.prepareEvents('alpha', 2);
    EventREST.prepareEvents('alpha', 2);
    EventREST.prepareEvents('alpha', 2);

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

    System.assertEquals(2, drainedCount('alpha', EventREST.MAX_EVENTS_PER_DRAIN));
    System.assertEquals(3, [SELECT COUNT() FROM EventData__c]);

    System.assertEquals(0, drainedCount('alpha', EventREST.MAX_EVENTS_PER_DRAIN));
    System.assertEquals(3, [SELECT COUNT() FROM EventData__c]);
  }

  // The endpoint honors a limit the caller sends, so the parameter reaches the query rather
  // than stopping at the request.
  @isTest
  static void doGetHonorsTheLimitItIsGiven() {
    insertEvents(3, null);

    RestContext.request = requestWithMaxEvents('2');
    RestContext.response = new RestResponse();

    Test.startTest();

    EventREST.doGet();

    Test.stopTest();

    List<Object> bundle = (List<Object>) JSON.deserializeUntyped(
      RestContext.response.responseBody.toString()
    );

    System.assertEquals(2, bundle.size());
    System.assertEquals(1, [SELECT COUNT() FROM EventData__c]);
  }

  // A limit the endpoint cannot use is refused, and nothing is drained or deleted on the way
  // out. Draining at the default instead would ignore the request.
  @isTest
  static void doGetRefusesALimitItCannotUse() {
    insertEvents(3, null);

    RestContext.request = requestWithMaxEvents('0');
    RestContext.response = new RestResponse();

    Test.startTest();

    EventREST.doGet();

    Test.stopTest();

    System.assertEquals(400, RestContext.response.statusCode);
    System.assert(
      RestContext.response.responseBody.toString().contains(EventREST.MAX_EVENTS_PARAM),
      RestContext.response.responseBody.toString()
    );
    System.assertEquals(3, [SELECT COUNT() FROM EventData__c]);
  }
}
