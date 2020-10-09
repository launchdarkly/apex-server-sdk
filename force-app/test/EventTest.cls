@isTest
private class EventTest {
    @isTest static void identify() {
        LDUser user = new LDUser.Builder('1').build();

        Event.Identify event = new Event.Identify(user, 123);

        String result = JSON.serialize(event.toGeneric());

        String expected = '{"creationDate":123,"user":{"key":"1"},"key":"1","kind":"identify"}';

        System.assertEquals(result, expected);
    }
}
