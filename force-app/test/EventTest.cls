@isTest
private class EventTest {
    @isTest static void identify() {
        LDUser user = new LDUser.Builder('1').build();

        Event.Identify event = new Event.Identify(user);

        String result = JSON.serialize(event.toGeneric());

        String expected = '{"user":{"key":"1"},"key":"1","kind":"identify"}';

        System.assertEquals(result, expected);
    }
}
