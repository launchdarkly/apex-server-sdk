public class LDValueArray extends LDValue {
    private final List<LDValue> value;

    public static LDValueArray fromList(List<LDValue> value) {
        return new LDValueArray(value);
    }

    private LDValueArray(List<LDValue> value) {
        // todo copy list to make immutable
        this.value = value;
    }

    public override LDValueType getType() {
        return LDValueType.CARRAY;
    }

    public override Integer size() {
        return this.value.size();
    }

    public override LDValue get(Integer index) {
        return this.value.get(index);
    }
}
