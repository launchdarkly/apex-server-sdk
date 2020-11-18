public class LDConfig {
    private final Boolean allAttributesPrivate;
    private final Integer maxEvents;

    private LDConfig(
        Boolean allAttributesPrivate,
        Integer maxEvents
    ) {
        this.allAttributesPrivate = allAttributesPrivate;
        this.maxEvents            = maxEvents;
    }

    public Boolean getAllAttributesPrivate() {
        return this.allAttributesPrivate;
    }

    public Integer getMaxEventsInQueue() {
        return this.maxEvents;
    }

    public class Builder {
        private Boolean allAttributesPrivate;
        private Integer maxEvents;

        public Builder() {
            this.allAttributesPrivate = false;
            this.maxEvents            = 1000;
        }

        public Builder setAllAttributesPrivate(Boolean allAttributesPrivate) {
            if (allAttributesPrivate == null) {
                this.allAttributesPrivate = false;
            } else {
                this.allAttributesPrivate = allAttributesPrivate;
            }

            return this;
        }

        public Builder setMaxEventsInQueue(Integer maxEvents) {
            if (maxEvents == null) {
                this.maxEvents = 1000;
            } else {
                this.maxEvents = maxEvents;
            }

            return this;
        }

        public LDConfig build() {
            return new LDConfig(
                this.allAttributesPrivate,
                this.maxEvents
            );
        }
    }
}
