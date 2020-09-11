public class LDValueString extends LDValue {
    private final String value;

    public static LDValueString fromString(String value) {
        return new LDValueString(value);
    }

    private LDValueString(String value) {
        this.value = value;
    }

    public override LDValueType getType() {
        return LDValueType.CSTRING;
    }

    public override String stringValue() {
        return this.value;
    }
}
