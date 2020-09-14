@isTest
private class LDUserTest {
    @isTest static void constructionAll() {
        LDValueObject custom = new LDValueObject.Builder()
            .set('a', LDValue.of('b'))
            .build();

        LDUser user = new LDUser.Builder('1')
            .setAnonymous(true)
            .setIP('2')
            .setFirstName('3')
            .setLastName('4')
            .setName('5')
            .setAvatar('6')
            .setCountry('7')
            .setSecondary('8')
            .setCustom(custom)
            .build();

        System.assertEquals(user.getKey(), '1');
        System.assertEquals(user.getAnonymous(), true);
        System.assertEquals(user.getIP(), '2');
        System.assertEquals(user.getFirstName(), '3');
        System.assertEquals(user.getLastName(), '4');
        System.assertEquals(user.getName(), '5');
        System.assertEquals(user.getAvatar(), '6');
        System.assertEquals(user.getCountry(), '7');
        System.assertEquals(user.getSecondary(), '8');
        System.assertEquals(user.getCustom(), custom);

        System.assertEquals(user.getAttribute('key').stringValue(), '1');
        System.assertEquals(user.getAttribute('ip').stringValue(), '2');
        System.assertEquals(user.getAttribute('firstName').stringValue(), '3');
        System.assertEquals(user.getAttribute('lastName').stringValue(), '4');
        System.assertEquals(user.getAttribute('name').stringValue(), '5');
        System.assertEquals(user.getAttribute('avatar').stringValue(), '6');
        System.assertEquals(user.getAttribute('country').stringValue(), '7');
        System.assertEquals(user.getAttribute('secondary').stringValue(), '8');
        System.assertEquals(user.getAttribute('a').stringValue(), 'b');
        System.assertEquals(user.getAttribute('unknown'), null);
    }

    @isTest static void constructionDefault() {
        LDUser user = new LDUser.Builder(null).build();

        System.assertEquals(user.getKey(), null);
        System.assertEquals(user.getAnonymous(), false);
        System.assertEquals(user.getIP(), null);
        System.assertEquals(user.getFirstName(), null);
        System.assertEquals(user.getLastName(), null);
        System.assertEquals(user.getName(), null);
        System.assertEquals(user.getAvatar(), null);
        System.assertEquals(user.getCountry(), null);
        System.assertEquals(user.getSecondary(), null);
        System.assertEquals(user.getCustom(), null);

        System.assertEquals(user.getAttribute('key'), null);
        System.assertEquals(user.getAttribute('ip'), null);
        System.assertEquals(user.getAttribute('firstName'), null);
        System.assertEquals(user.getAttribute('lastName'), null);
        System.assertEquals(user.getAttribute('name'), null);
        System.assertEquals(user.getAttribute('avatar'), null);
        System.assertEquals(user.getAttribute('country'), null);
        System.assertEquals(user.getAttribute('secondary'), null);
        System.assertEquals(user.getAttribute('unknown'), null);
    }
}
