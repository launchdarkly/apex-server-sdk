public class Event {
    public static String userToContextKind(LDUser user) {
        System.assertNotEquals(user, null);

        if (user.getAnonymous()) {
            return 'anonymousUser';
        } else {
            return 'user';
        }
    }

    public class Identify {
        private final String key;
        private final Object user;
        private final Long   now;

        public Identify(LDUser user, Long now, Boolean allAttributesPrivate) {
            System.assertNotEquals(user, null);
            System.assertNotEquals(now, null);
            System.assertNotEquals(allAttributesPrivate, null);

            this.key  = user.getKey();
            this.user = user.toGeneric(allAttributesPrivate);
            this.now  = now;
        }

        public Object toGeneric() {
            Map<String, Object> event = new Map<String, Object>();

            event.put('kind', 'identify');
            event.put('key', this.key);
            event.put('user', this.user);
            event.put('creationDate', this.now);

            return (Object)event;
        }
    }

    public class Alias {
        private final String key;
        private final String contextKind;
        private final String previousKey;
        private final string previousContextKind;
        private final Long   now;

        public Alias(LDUser currentUser, LDUser previousUser, Long now) {
            System.assertNotEquals(currentUser, null);
            System.assertNotEquals(previousUser, null);
            System.assertNotEquals(now, null);

            this.key                 = currentUser.getKey();
            this.contextKind         = Event.userToContextKind(currentUser);
            this.previousKey         = previousUser.getKey();
            this.previousContextKind = Event.userToContextKind(previousUser);
            this.now                 = now;
        }

        public Object toGeneric() {
            Map<String, Object> event = new Map<String, Object>();

            event.put('kind', 'alias');
            event.put('key', this.key);
            event.put('contextKind', this.contextKind);
            event.put('previousKey', this.previousKey);
            event.put('previousContextKind', this.previousContextKind);
            event.put('creationDate', this.now);

            return (Object)event;
        }
    }

    public class Custom {
        private final Object  user;
        private final String  key;
        private final String  contextKind;
        private final Double  optionalMetric;
        private final LDValue optionalValue;
        private final Long    now;

        public Custom(
            LDUser  user,
            String  key,
            Double  optionalMetric,
            LDValue optionalValue,
            Long    now,
            Boolean allAttributesPrivate
        ) {
            System.assertNotEquals(user, null);
            System.assertNotEquals(key, null);
            System.assertNotEquals(now, null);
            System.assertNotEquals(allAttributesPrivate, null);

            this.user           = user.toGeneric(allAttributesPrivate);
            this.key            = key;
            this.optionalMetric = optionalMetric;
            this.optionalValue  = optionalValue;
            this.now            = now;

            if (user.getAnonymous()) {
                this.contextKind = Event.userToContextKind(user);
            }
        }

        public Object toGeneric() {
            Map<String, Object> event = new Map<String, Object>();

            event.put('kind', 'custom');
            event.put('key', key);
            event.put('user', this.user);

            if (this.optionalMetric != null) {
                event.put('metricValue', this.optionalMetric);
            }

            if (this.optionalValue != null) {
                event.put('data', this.optionalValue.toGeneric());
            }

            if (this.contextKind != null) {
                event.put('contextKind', this.contextKind);
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
        private final String   contextKind;
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
            Long             now,
            Boolean          allAttributesPrivate
        ) {
            System.assertNotEquals(key, null);
            System.assertNotEquals(trackEvents, null);
            System.assertNotEquals(debug, null);
            System.assertNotEquals(now, null);

            this.key                  = key;
            this.version              = version;
            this.variation            = variation;
            this.prereqOf             = prereqOf;
            this.trackEvents          = trackEvents;
            this.debugEventsUntilDate = debugEventsUntilDate;
            this.debug                = debug;
            this.unknown              = unknown;
            this.now                  = now;
            
            if (user != null) {
                this.user = user.toGeneric(allAttributesPrivate);

                if (user.getAnonymous()) {
                    this.contextKind = Event.userToContextKind(user);
                }
            }
            
            if (value != null) {
                this.value = value.toGeneric();
            }

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
            this.defaultValue         = (Object)obj.get('default');
            this.prereqOf             = (String)obj.get('prereqOf');
            this.trackEvents          = (Boolean)obj.get('trackEvents');
            this.debugEventsUntilDate = (Double)obj.get('debugEventsUntilDate');
            this.reason               = (Object)obj.get('reason');
            this.debug                = (Boolean)obj.get('debug');
            this.unknown              = (Boolean)obj.get('unknown');
            this.contextKind          = (String)obj.get('contextKind');
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
            event.put('default', this.defaultValue);
            
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

            if (this.contextKind != null) {
                event.put('contextKind', this.contextKind);
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
