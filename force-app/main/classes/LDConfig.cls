public class LDConfig {
    private final String key;

    private LDConfig(
        String key
    ) {
        this.key = key;
    }

    public String getKey() {
        return this.key;
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

        public LDConfig build() {
            return new LDConfig(this.key);
        }
    }
}
