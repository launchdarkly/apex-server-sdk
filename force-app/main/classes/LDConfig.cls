public class LDConfig {
    private final Boolean allAttributesPrivate;

    private LDConfig(
        Boolean allAttributesPrivate
    ) {
        this.allAttributesPrivate = allAttributesPrivate;
    }

    public Boolean getAllAttributesPrivate() {
        return this.allAttributesPrivate;
    }

    public class Builder {
        private Boolean allAttributesPrivate;

        public Builder() {
            this.allAttributesPrivate = false;
        }

        public Builder setAllAttributesPrivate(Boolean allAttributesPrivate) {
            if (allAttributesPrivate == null) {
                this.allAttributesPrivate = false;
            } else {
                this.allAttributesPrivate = allAttributesPrivate;
            }

            return this;
        }

        public LDConfig build() {
            return new LDConfig(
                this.allAttributesPrivate
            );
        }
    }
}
