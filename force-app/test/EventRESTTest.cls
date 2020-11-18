@isTest
private class EventRESTTest {
    @isTest static void basicBundle() {
        EventSink sink = new EventSink(1000);
        
        sink.sinkIdentify(new Event.Identify(new LDUser.Builder('abc').build(), 0, false));
        
        Object bundle = EventREST.prepareEvents();
        
        Object bundleIso = JSON.deserializeUntyped(JSON.serialize(bundle));
        
        String expectedRaw = '[{"creationDate":0,"user":{"key":"abc"},"key":"abc","kind":"identify"}]';
        
        System.assertEquals(bundleIso, JSON.deserializeUntyped(expectedRaw));
    }
}
