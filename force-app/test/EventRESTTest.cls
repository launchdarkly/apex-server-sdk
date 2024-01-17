@isTest
private class EventRESTTest {
  @isTest
  static void basicBundle() {
    EventSink sink = new EventSink(1000);

    sink.sinkIdentify(new LDEvent.Identify(new LDUser.Builder('abc').build(), 0, false));

    Object bundle = EventREST.prepareEvents();

    Object bundleIso = JSON.deserializeUntyped(JSON.serialize(bundle));

    String expectedRaw = '[{"creationDate":0,"user":{"key":"abc"},"key":"abc","kind":"identify"}]';

    System.assertEquals(bundleIso, JSON.deserializeUntyped(expectedRaw));
  }

  @isTest
  static void restContext() {
    EventSink sink = new EventSink(1000);

    sink.sinkIdentify(new LDEvent.Identify(new LDUser.Builder('abc').build(), 0, false));

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
}
