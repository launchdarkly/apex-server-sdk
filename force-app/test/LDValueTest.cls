@isTest
private class LDValueTest {
    @isTest static void basicBoolean() {
        LDValue value = LDValue.of(true);
        System.assertEquals(value.getType(), LDValueType.CBOOLEAN);
        System.assertEquals(value.booleanValue(), true);
    }

    @isTest static void basicNumber() {
        Double x = 3.3;
        LDValue value = LDValue.of(x);
        System.assertEquals(value.getType(), LDValueType.CNUMBER);
        System.assertEquals(value.doubleValue(), x);
    }
}
