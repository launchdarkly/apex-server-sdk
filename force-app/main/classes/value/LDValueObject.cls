public class LDValueObject extends LDValue {
    private final Map<String, LDValue> value;

    public static LDValueObject fromMap(Map<String, LDValue> value) {
        if (value == null) {
            return null;
        } else {
            return new LDValueObject(value);
        }
    }

    private LDValueObject(Map<String, LDValue> value) {
        this.value = new Map<String, LDValue>(value);
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

    public class Builder {
        private Map<String, LDValue> value;

        public Builder() {
            this.value = new Map<String, LDValue>();
        }

        public Builder set(String key, LDValue value) {
            this.value.put(key, value);

            return this;
        }

        public LDValueObject build() {
            return new LDValueObject(this.value);
        }
    }
}
