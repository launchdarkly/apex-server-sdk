@isTest
private class EventTest {
    @isTest static void identify() {
        LDUser user = new LDUser.Builder('1').build();

        Event.Identify event = new Event.Identify(user, 123, false);

        String result = JSON.serialize(event.toGeneric());

        String expected = '{"creationDate":123,"user":{"key":"1"},"key":"1","kind":"identify"}';

        System.assertEquals(result, expected);
    }

    @isTest static void aliasNotAnonymous() {
        LDUser currentUser = new LDUser.Builder('current').build();
        LDUser previousUser = new LDUser.Builder('previous').build();

        Event.Alias event = new Event.Alias(currentUser, previousUser, 52);

        Object result = (Object)JSON.deserializeUntyped(JSON.serialize(event.toGeneric()));

        String expected =
              '{'
            + '"creationDate":52,'
            + '"key":"current",' 
            + '"contextKind": "user",'
            + '"previousKey":"previous",'
            + '"previousContextKind": "user",'
            + '"kind":"alias"'
            + '}';

        System.assertEquals(result, JSON.deserializeUntyped(expected));
    }

    @isTest static void aliasAnonymous() {
        LDUser currentUser = new LDUser.Builder('current').setAnonymous(true).build();
        LDUser previousUser = new LDUser.Builder('previous').setAnonymous(true).build();

        Event.Alias event = new Event.Alias(currentUser, previousUser, 19);

        Object result = (Object)JSON.deserializeUntyped(JSON.serialize(event.toGeneric()));

        String expected =
              '{'
            + '"creationDate":19,'
            + '"key":"current",' 
            + '"contextKind": "anonymousUser",'
            + '"previousKey":"previous",'
            + '"previousContextKind": "anonymousUser",'
            + '"kind":"alias"'
            + '}';

        System.assertEquals(result, JSON.deserializeUntyped(expected));
    }

    @isTest static void customAnonymous() {
        LDUser user = new LDUser.Builder('alice').setAnonymous(true).build();

        Event.Custom event = new Event.Custom(user, 'view', null, null, 5, false);

        Object result = (Object)JSON.deserializeUntyped(JSON.serialize(event.toGeneric()));

        String expected =
              '{'
            + '"creationDate":5,'
            + '"key":"view",'
            + '"user": {"key":"alice","anonymous":true},'
            + '"contextKind": "anonymousUser",'
            + '"kind":"custom"'
            + '}';

        System.assertEquals(result, JSON.deserializeUntyped(expected));
    }
}
