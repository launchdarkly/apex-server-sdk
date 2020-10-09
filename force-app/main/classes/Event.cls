public class Event {
    public class Identify {
        private final LDUser user;
        private final Long   now;

        public Identify(LDUser user, Long now) {
            System.assertNotEquals(user, null);
            System.assertNotEquals(now, null);

            this.user = user;
            this.now  = now;
        }

        public Object toGeneric() {
            Map<String, Object> event = new Map<String, Object>();

            event.put('kind', 'identify');
            event.put('key', this.user.getKey());
            event.put('user', this.user.toGeneric());
            event.put('creationDate', this.now);

            return (Object)event;
        }
    }

    public class Custom {
        private final LDUser  user;
        private final String  key;
        private final Double  optionalMetric;
        private final LDValue optionalValue;
        private final Long    now;

        public Custom(
            LDUser  user,
            String  key,
            Double  optionalMetric,
            LDValue optionalValue,
            Long    now
        ) {
            System.assertNotEquals(user, null);
            System.assertNotEquals(key, null);
            System.assertNotEquals(now, null);

            this.user           = user;
            this.key            = key;
            this.optionalMetric = optionalMetric;
            this.optionalValue  = optionalValue;
            this.now            = now;
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
            
            event.put('creationDate', this.now);

            return (Object)event;
        }
    }

    public class Feature {
        private final String   key;
        private final Object   user;
        private final Integer  variation;
        private final Object   value;
        private final Object   defaultValue;
        private final Integer  version;
        private final String   prereqOf;
        private final Boolean  trackEvents;
        private final Double   debugEventsUntilDate;
        private final Object   reason;
        private final Boolean  debug;
        private final Boolean  unknown;
        private final Long     now;

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
            Boolean          unknown,
            Long             now
        ) {
            System.assertNotEquals(key, null);
            System.assertNotEquals(value, null);
            System.assertNotEquals(trackEvents, null);
            System.assertNotEquals(debug, null);
            System.assertNotEquals(now, null);

            this.key                  = key;
            this.user                 = user.toGeneric();
            this.version              = version;
            this.variation            = variation;
            this.value                = value.toGeneric();
            this.prereqOf             = prereqOf;
            this.trackEvents          = trackEvents;
            this.debugEventsUntilDate = debugEventsUntilDate;
            this.debug                = debug;
            this.unknown              = unknown;
            this.now                  = now;

            if (defaultValue != null) {
                this.defaultValue = defaultValue.toGeneric();
            }

            if (reason != null) {
                this.reason = reason.toGeneric();
            }
        }

        public Feature(Object raw) {
            System.assertNotEquals(raw, null);

            Map<String, Object> obj = (Map<String, Object>)raw;

            this.key                  = (String)obj.get('key');
            this.user                 = (Object)obj.get('user');
            this.version              = (Integer)obj.get('version');
            this.variation            = (Integer)obj.get('variation');
            this.value                = (Object)obj.get('value');
            this.defaultValue         = (Object)obj.get('defaultValue');
            this.prereqOf             = (String)obj.get('prereqOf');
            this.trackEvents          = (Boolean)obj.get('trackEvents');
            this.debugEventsUntilDate = (Double)obj.get('debugEventsUntilDate');
            this.reason               = (Object)obj.get('reason');
            this.debug                = (Boolean)obj.get('debug');
            this.unknown              = (Boolean)obj.get('unknown');
            this.now                  = (Long)obj.get('creationDate');
        }

        public Object toGeneric() {
            Map<String, Object> event = new Map<String, Object>();

            event.put('kind', 'feature');
            event.put('key', this.key);
            event.put('user', this.user);
            event.put('version', this.version);
            event.put('variation', this.variation);
            event.put('value', this.value);
            event.put('defaultValue', this.defaultValue);
            
            if (this.prereqOf != null) {
                event.put('prereqOf', this.prereqOf);
            }

            event.put('trackEvents', this.trackEvents);
            
            if (this.debugEventsUntilDate != null) {
                event.put('debugEventsUntilDate', this.debugEventsUntilDate);
            }

            if (this.reason != null) {
                event.put('reason', this.reason);
            }

            event.put('debug', this.debug);
            event.put('unknown', this.unknown);
            event.put('creationDate', this.now);

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

        public Object getDefaultValue() {
            return this.defaultValue;
        }

        public Object getValue() {
            return this.value;
        }

        public Boolean getUnknown() {
            return this.unknown;
        }
        
        public Boolean getTrackEvents() {
            return this.trackEvents;
        }
    }
}
