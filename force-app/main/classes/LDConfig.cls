public class LDConfig {
    private final String  key;
    private final Boolean allAttributesPrivate;

    private LDConfig(
        String  key,
        Boolean allAttributesPrivate
    ) {
        this.key                  = key;
        this.allAttributesPrivate = allAttributesPrivate;
    }

    public String getKey() {
        return this.key;
    }

    public Boolean getAllAttributesPrivate() {
        return this.allAttributesPrivate;
    }

    public class Builder {
        private String  key;
        private Boolean allAttributesPrivate;

        public Builder(String key) {
            this.key                  = key;
            this.allAttributesPrivate = false;
        }

        public Builder setKey(String key) {
            this.key = key;

            return this;
        }

        public Builder setAllAttributesPrivate(Boolean allAttributesPrivate) {
            this.allAttributesPrivate = allAttributesPrivate;

            return this;
        }

        public LDConfig build() {
            return new LDConfig(
                this.key,
                this.allAttributesPrivate
            );
        }
    }
}
