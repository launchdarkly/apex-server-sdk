public class LDUser {
    private final String key;

    private LDUser(String key) {
        this.key = key;
    }

    public String getKey() {
        return this.key;
    }

    public String getSecondary() {
        return '';
    }

    public LDValue getAttribute(String attribute) {
        return LDValue.of(this.key);
    }

    public class Builder {
        private String key;

        public Builder(String key) {
            this.key = key;
        }

        public Builder setKey(String key) {
            this.key = key;

            return this;
        }

        public LDUser build() {
            return new LDUser(this.key);
        }
    }
}
