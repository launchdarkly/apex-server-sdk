public class LDValueObject extends LDValue {
    private final Map<String, LDValue> value;

    public static LDValueObject fromMap(Map<String, LDValue> value) {
        return new LDValueObject(value);
    }

    private LDValueObject(Map<String, LDValue> value) {
        // todo copy map to make immutable
        this.value = value;
    }

    public override LDValueType getType() {
        return LDValueType.CObject;
    }

    public override Integer size() {
        return this.value.size();
    }

    public override LDValue get(String index) {
        return this.value.get(index);
    }
}
