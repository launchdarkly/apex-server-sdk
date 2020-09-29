public class Event {
    public class Identify {
        private final LDUser user;

        public Identify(LDUser user) {
            System.assertNotEquals(user, null);

            this.user = user;
        }

        public Object toGeneric() {
            Map<String, Object> event = new Map<String, Object>();

            event.put('kind', 'identify');
            event.put('key', this.user.getKey());
            event.put('user', this.user.toGeneric());

            return (Object)event;
        }
    }

    public class Custom {
        private final LDUser  user;
        private final String  key;
        private final Double  optionalMetric;
        private final LDValue optionalValue;

        public Custom(
            LDUser  user,
            String  key,
            Double  optionalMetric,
            LDValue optionalValue
        ) {
            System.assertNotEquals(user, null);
            System.assertNotEquals(key, null);

            this.user           = user;
            this.key            = key;
            this.optionalMetric = optionalMetric;
            this.optionalValue  = optionalValue;
        }

        public Object toGeneric() {
            Map<String, Object> event = new Map<String, Object>();

            event.put('kind', 'custom');
            event.put('key', key);
            event.put('user', this.user.toGeneric());

            if (this.optionalMetric != null) {
                event.put('metricValue', this.optionalMetric);
            }

            if (this.optionalValue != null) {
                event.put('data', this.optionalValue.toGeneric());
            }

            return (Object)event;
        }
    }

    public class Feature {
        private final String           key;
        private final LDUser           user;
        private final Integer          variation;
        private final LDValue          value;
        private final LDValue          defaultValue;
        private final Integer          version;
        private final String           prereqOf;
        private final Boolean          trackEvents;
        private final Double           debugEventsUntilDate;
        private final EvaluationReason reason;
        private final Boolean          debug;
        private final Boolean          unknown;

        public Feature(
            String           key,
            LDUser           user,
            Integer          version,
            Integer          variation,
            LDValue          value,
            LDValue          defaultValue,
            EvaluationReason reason,
            String           prereqOf,
            Boolean          trackEvents,
            Double           debugEventsUntilDate,
            Boolean          debug,
            Boolean          unknown
        ) {
            System.assertNotEquals(key, null);
            System.assertNotEquals(value, null);
            System.assertNotEquals(trackEvents, null);
            System.assertNotEquals(debug, null);

            this.key                  = key;
            this.user                 = user;
            this.version              = version;
            this.variation            = variation;
            this.value                = value;
            this.defaultValue         = defaultValue;
            this.prereqOf             = prereqOf;
            this.trackEvents          = trackEvents;
            this.debugEventsUntilDate = debugEventsUntilDate;
            this.reason               = reason;
            this.debug                = debug;
            this.unknown              = unknown;
        }

        public Object toGeneric() {
            Map<String, Object> event = new Map<String, Object>();

            event.put('kind', 'feature');

            return event;
        }

        public String getKey() {
            return this.key;
        }

        public Integer getVariation() {
            return this.variation;
        }

        public Integer getVersion() {
            return this.version;
        }

        public LDValue getDefaultValue() {
            return this.defaultValue;
        }

        public LDValue getValue() {
            return this.value;
        }

        public Boolean getUnknown() {
            return this.unknown;
        }
    }
}
