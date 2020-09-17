public class LDValueArray extends LDValue {
    private final List<LDValue> value;

    public static LDValueArray fromList(List<LDValue> value) {
        if (value == null) {
            return null;
        } else {
            return new LDValueArray(value);
        }
    }

    private LDValueArray(List<LDValue> value) {
        this.value = new List<LDValue>(value);
    }

    public override LDValueType getType() {
        return LDValueType.CARRAY;
    }

    public override Integer size() {
        return this.value.size();
    }

    public override LDValue get(Integer index) {
        if (this.value.size() > index) {
            return this.value.get(index);
        } else {
            return null;
        }
    }

    public class Builder {
        private List<LDValue> value;

        public Builder() {
            this.value = new List<LDValue>();
        }

        public Builder add(LDValue value) {
            this.value.add(value);

            return this;
        }

        public LDValueArray build() {
            return new LDValueArray(this.value);
        }
    }
}
