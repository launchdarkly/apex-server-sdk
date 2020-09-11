public class DataModel {
    public class WeightedVariation {
        private final Integer variation;
        private final Double  weight;

        public WeightedVariation(Object raw) {
            System.assertNotEquals(raw, null);

            Map<String, Object> obj = (Map<String, Object>)raw;

            this.variation = (Integer)obj.get('variation');
            this.weight    = (Double)obj.get('weight');

            System.assertNotEquals(this.variation, null);
            System.assertNotEquals(this.weight, null);
        }

        public Integer getVariation() {
            return this.variation;
        }

        public Double getWeight() {
            return this.weight;
        }
    }

    public class Rollout {
        private final String bucketBy;
        private final List<WeightedVariation> variations;

        public Rollout(Object raw) {
            System.assertNotEquals(raw, null);

            Map<String, Object> obj = (Map<String, Object>)raw;

            this.bucketBy   = (String)obj.get('bucketBy');
            this.variations = null;

            List<Object> variations = (List<Object>)obj.get('variations');

            if (variations != null) {
                this.variations = new List<WeightedVariation>();

                for (Object variation : variations) {
                    this.variations.add(new DataModel.WeightedVariation(variation));
                }
            }
        }

        public String getBucketBy() {
            return this.bucketBy;
        }

        public List<WeightedVariation> getVariations() {
            return this.variations;
        }
    }

    public class VariationOrRollout {
        private final Integer           variation;
        private final DataModel.Rollout rollout;

        public VariationOrRollout(Object raw) {
            System.assertNotEquals(raw, null);

            Map<String, Object> obj = (Map<String, Object>)raw;

            this.variation = (Integer)obj.get('variation');
            this.rollout   = null;

            Object rollout = (Object)obj.get('rollout');

            if (rollout != null) {
                this.rollout = new DataModel.Rollout(rollout);
            }
        }

        public Integer getVariation() {
            return this.variation;
        }

        public DataModel.Rollout getRollout() {
            return this.rollout;
        }
    }

    public class Clause {
        private final String        attribute;
        private final String        operator;
        private final Boolean       negate;
        private final List<LDValue> values;

        public Clause(Object raw) {
            System.assertNotEquals(raw, null);

            Map<String, Object> obj = (Map<String, Object>)raw;

            this.attribute = (String)obj.get('attribute');
            this.operator  = (String)obj.get('op');
            this.negate    = (Boolean)obj.get('negate');
            this.values    = new List<LDValue>();

            List<Object> values = (List<Object>)obj.get('values');

            if (values != null) {
                for (Object value : values) {
                    this.values.add(LDValue.ofGeneric(value));
                }
            }

            System.assertNotEquals(this.attribute, null);
            System.assertNotEquals(this.operator, null);
            System.assertNotEquals(this.negate, null);
            System.assertNotEquals(this.values, null);
        }

        public String getAttribute() {
            return this.attribute;
        }

        public String getOperator() {
            return this.operator;
        }

        public Boolean isNegate() {
            return this.negate;
        }

        public List<LDValue> getValues() {
            return this.values;
        }
    }

    public class Rule {
        private final String                       ruleId;
        private final Boolean                      trackEvents;
        private final List<Clause>                 clauses;
        private final DataModel.VariationOrRollout vor;

        public Rule(Object raw) {
            System.assertNotEquals(raw, null);

            Map<String, Object> obj = (Map<String, Object>)raw;

            this.ruleId      = (String)obj.get('id');
            this.trackEvents = (Boolean)obj.get('trackEvents');
            this.clauses     = new List<Clause>();

            List<Object> clauses = (List<Object>)obj.get('clauses');

            if (clauses != null) {
                for (Object clause : clauses) {
                    this.clauses.add(new DataModel.Clause(clause));
                }
            }

            this.vor = new DataModel.VariationOrRollout(raw);

            System.assertNotEquals(this.ruleId, null);
            System.assertNotEquals(this.trackEvents, null);
            System.assertNotEquals(this.clauses, null);
            System.assertNotEquals(this.vor, null);
        }

        public String getId() {
            return this.ruleId;
        }

        public Boolean shouldTrackEvents() {
            return this.trackEvents;
        }

        public List<Clause> getClauses() {
            return this.clauses;
        }

        public DataModel.VariationOrRollout getVariationOrRollout() {
            return this.vor;
        }
    }

    public class Target {
        private final Integer      variation;
        private final List<String> values;

        public Target(Object raw) {
            System.assertNotEquals(raw, null);

            Map<String, Object> obj = (Map<String, Object>)raw;

            this.variation = (Integer)obj.get('variation');
            this.values    = (List<String>)obj.get('values');

            System.assertNotEquals(this.variation, null);
            System.assertNotEquals(this.values, null);
        }

        public Integer getVariation() {
            return this.variation;
        }

        public List<String> getValues() {
            return this.values;
        }
    }

    public class Prerequisite {
        private final Integer variation;
        private final String  key;

        public Prerequisite(Object raw) {
            System.assertNotEquals(raw, null);

            Map<String, Object> obj = (Map<String, Object>)raw;

            this.variation = (Integer)obj.get('variation');
            this.key       = (String)obj.get('key');

            System.assertNotEquals(this.variation, null);
            System.assertNotEquals(this.key, null);
        }

        public Integer getVariation() {
            return this.variation;
        }

        public String getKey() {
            return this.key;
        }
    }

    public class SegmentRule {
        private final String       ruleId;
        private final List<Clause> clauses;
        private final Double       weight;
        private final String       bucketBy;

        public SegmentRule(Object raw) {
            System.assertNotEquals(raw, null);

            Map<String, Object> obj = (Map<String, Object>)raw;

            this.ruleId   = (String)obj.get('id');
            this.clauses  = new List<Clause>();
            this.weight   = (Double)obj.get('weight');
            this.bucketBy = (String)obj.get('bucketBy');

            List<Object> clauses = (List<Object>)obj.get('clauses');

            if (clauses != null) {
                for (Object clause : clauses) {
                    this.clauses.add(new DataModel.Clause(clause));
                }
            }

            System.assertNotEquals(this.ruleId, null);
            System.assertNotEquals(this.clauses, null);
            System.assertNotEquals(this.weight, null);
            System.assertNotEquals(this.bucketBy, null);
        }

        public String getId() {
            return this.ruleId;
        }

        public List<CLause> getClauses() {
            return this.clauses;
        }

        public Double getWeight() {
            return this.weight;
        }

        public String getBucketBy() {
            return this.bucketBy;
        }
    }

    public class Segment {
        private final String                      key;
        private final Set<String>                 included;
        private final Set<String>                 excluded;
        private final String                      salt;
        private final List<DataModel.SegmentRule> rules;
        private final Integer                     version;

        public Segment(Object raw) {
            System.assertNotEquals(raw, null);

            Map<String, Object> obj = (Map<String, Object>)raw;

            this.key      = (String)obj.get('key');
            this.included = new Set<String>();
            this.excluded = new Set<String>();
            this.salt     = (String)obj.get('salt');
            this.rules    = new List<DataModel.SegmentRule>();
            this.version  = (Integer)obj.get('version');

            // included
            List<String> included = (List<String>)obj.get('included');

            if (included != null) {
                this.included = new Set<String>(included);
            }

            // excluded
            List<String> excluded = (List<String>)obj.get('excluded');

            if (excluded != null) {
                this.excluded = new Set<String>(excluded);
            }

            // rules
            List<Object> rules = (List<Object>)obj.get('rules');

            if (rules != null) {
                for (Object rule : rules) {
                    this.rules.add(new DataModel.SegmentRule(rule));
                }
            }

            System.assertNotEquals(this.key, null);
            System.assertNotEquals(this.included, null);
            System.assertNotEquals(this.excluded, null);
            System.assertNotEquals(this.salt, null);
            System.assertNotEquals(this.rules, null);
            System.assertNotEquals(this.version, null);
        }

        public String getKey() {
            return this.key;
        }

        public Set<String> getIncluded() {
            return this.included;
        }

        public Set<String> getExcluded() {
            return this.excluded;
        }

        public String getSalt() {
            return this.salt;
        }

        public List<DataModel.SegmentRule> getRules() {
            return this.rules;
        }

        public Integer getVersion() {
            return this.version;
        }
    }

    public class Flag {
        private final Integer                      version;
        private final String                       key;
        private final Boolean                      fieldOn;
        private final List<LDValue>                variations;
        private final Integer                      offVariation; // may be null
        private final DataModel.VariationOrRollout fallthrough;
        private final List<DataModel.Target>       targets;
        private final List<DataModel.Prerequisite> prerequisites;
        private final List<DataModel.Rule>         rules;
        private final String                       salt;

        public Flag(String raw) {
            Map<String, Object> obj = (Map<String, Object>)
                JSON.deserializeUntyped(raw);

            this.version       = (Integer)obj.get('version');
            this.key           = (String)obj.get('key');
            this.fieldOn       = (Boolean)obj.get('on');
            this.variations    = new List<LDValue>();
            this.offVariation  = (Integer)obj.get('offVariation');
            this.targets       = new List<DataModel.Target>();
            this.prerequisites = new List<DataModel.Prerequisite>();
            this.rules         = new List<DataModel.Rule>();
            this.salt          = (String)obj.get('salt');

            // variations
            List<Object> variations = (List<Object>)obj.get('variations');

            for (Object variation : variations) {
                this.variations.add(LDValue.ofGeneric(variation));
            }

            // fallthrough
            this.fallthrough = new
                DataModel.VariationOrRollout((Object)obj.get('fallthrough'));

            // targets
            List<Object> targets = (List<Object>)obj.get('targets');

            if (targets != null) {
                for (Object target : targets) {
                    this.targets.add(new DataModel.Target(target));
                }
            }

            // prerequisites
            List<Object> prerequisites = (List<Object>)obj.get('prerequisites');

            if (prerequisites != null) {
                for (Object prerequisite : prerequisites) {
                    this.prerequisites.add(new DataModel.Prerequisite(prerequisite));
                }
            }

            // rules
            List<Object> rules = (List<Object>)obj.get('rules');

            if (rules != null) {
                for (Object rule : rules) {
                    this.rules.add(new DataModel.Rule(rule));
                }
            }

            System.assertNotEquals(this.version, null);
            System.assertNotEquals(this.key, NULL);
            System.assertNotEquals(this.fieldOn, NULL);
            System.assertNotEquals(this.variations, NULL);
            System.assertNotEquals(this.prerequisites, NULL);
            System.assertNotEquals(this.rules, NULL);
            System.assertNotEquals(this.salt, NULL);
        }

        public Integer getVersion() {
            return this.version;
        }

        public String getKey() {
            return this.key;
        }

        public Boolean isOn() {
            return this.fieldOn;
        }

        public Integer getOffVariation() {
            return this.offVariation;
        }

        public List<LDValue> getVariations() {
            return this.variations;
        }

        public DataModel.VariationOrRollout getFallthrough() {
            return this.fallthrough;
        }

        public List<DataModel.Target> getTargets() {
            return this.targets;
        }

        public List<DataModel.Prerequisite> getPrerequisites() {
            return this.prerequisites;
        }

        public List<DataModel.Rule> getRules() {
            return this.rules;
        }

        public String getSalt() {
            return this.salt;
        }
    }
}
