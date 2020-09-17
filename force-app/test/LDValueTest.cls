@isTest
private class LDValueTest {
    @isTest static void basicBoolean() {
        Boolean x = true;
        LDValue value = LDValue.of(x);
        System.assertEquals(value.getType(), LDValueType.CBOOLEAN);
        System.assertEquals(value.booleanValue(), x);
    }

    @isTest static void basicDouble() {
        Double x = 3.3;
        LDValue value = LDValue.of(x);
        System.assertEquals(value.getType(), LDValueType.CNUMBER);
        System.assertEquals(value.doubleValue(), x);
    }

    @isTest static void basicInteger() {
        Integer x = 7;
        LDValue value = LDValue.of(x);
        System.assertEquals(value.getType(), LDValueType.CNUMBER);
        System.assertEquals(value.intValue(), x);
    }

    @isTest static void basicString() {
        String x = 'hello';
        LDValue value = LDValue.of(x);
        System.assertEquals(value.getType(), LDValueType.CSTRING);
        System.assertEquals(value.stringValue(), x);
    }

    @isTest static void basicObject() {
        LDValue value = new LDValueObject.Builder().set('a', LDValue.of(true)).build();
        System.assertEquals(value.getType(), LDValueType.COBJECT);
        System.assertEquals(value.size(), 1);
        System.assertEquals(value.get('b'), null);
        LDValue child = value.get('a');
        System.assertEquals(child.getType(), LDValueType.CBOOLEAN);
        System.assertEquals(child.booleanValue(), true);
    }

    @isTest static void basicArray() {
        LDValue value = new LDValueArray.Builder().add(LDValue.of(true)).build();
        System.assertEquals(value.getType(), LDValueType.CARRAY);
        System.assertEquals(value.size(), 1);
        System.assertEquals(value.get(3), null);
        LDValue child = value.get(0);
        System.assertEquals(child.getType(), LDValueType.CBOOLEAN);
        System.assertEquals(child.booleanValue(), true);
    }
}
