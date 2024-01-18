public class DataModel {
  public static WeightedVariation parseWeightedVariation(Object raw) {
    System.assertNotEquals(raw, null);

    Map<String, Object> obj = (Map<String, Object>) raw;

    return new WeightedVariation(
      (Integer) obj.get('variation'),
      (Double) obj.get('weight'),
      (Boolean) obj.get('untracked')
    );
  }

  public class WeightedVariation {
    private final Integer variation;
    private final Double weight;
    private final Boolean untracked;

    public WeightedVariation(Integer variation, Double weight, Boolean untracked) {
      System.assertNotEquals(variation, null);
      System.assertNotEquals(weight, null);

      this.variation = variation;
      this.weight = weight;
      this.untracked = untracked;

      if (untracked == null) {
        this.untracked = false;
      }
    }

    public Boolean isUntracked() {
      return this.untracked;
    }

    public Integer getVariation() {
      return this.variation;
    }

    public Double getWeight() {
      return this.weight;
    }
  }

  public enum RolloutKind {
    ROLLOUT,
    EXPERIMENT
  }

  public class Rollout {
    private RolloutKind rolloutKindFromString(String kind) {
      switch on kind {
        when 'rollout' {
          return RolloutKind.ROLLOUT;
        }
        when 'experiment' {
          return RolloutKind.EXPERIMENT;
        }
      }

      return null;
    }

    public String bucketBy;
    public List<WeightedVariation> variations;
    public RolloutKind kind;
    public Integer seed;

    public Rollout() {
    }

    public Rollout(Object raw) {
      System.assertNotEquals(raw, null);

      Map<String, Object> obj = (Map<String, Object>) raw;

      this.bucketBy = (String) obj.get('bucketBy');
      this.variations = new List<WeightedVariation>();
      this.seed = (Integer) obj.get('seed');

      List<Object> variations = (List<Object>) obj.get('variations');

      if (variations != null) {
        for (Object variation : variations) {
          this.variations.add(DataModel.parseWeightedVariation(variation));
        }
      }

      String kind = (String) obj.get('kind');

      if (kind == null) {
        this.kind = RolloutKind.ROLLOUT;
      } else {
        this.kind = this.rolloutKindFromString(kind);
      }
    }

    public String getBucketBy() {
      return this.bucketBy;
    }

    public List<WeightedVariation> getVariations() {
      return this.variations;
    }

    public RolloutKind getKind() {
      return this.kind;
    }

    public Integer getSeed() {
      return this.seed;
    }
  }

  public class VariationOrRollout {
    public Integer variation;
    public DataModel.Rollout rollout;

    public VariationOrRollout() {
    }

    public VariationOrRollout(Object raw) {
      System.assertNotEquals(raw, null);

      Map<String, Object> obj = (Map<String, Object>) raw;

      this.variation = (Integer) obj.get('variation');
      this.rollout = null;

      Object rollout = (Object) obj.get('rollout');

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
    public String attribute;
    public String operator;
    public Boolean negate;
    public List<LDValue> values;

    public Clause(String attribute, String operator) {
      this.attribute = attribute;
      this.operator = operator;
      this.negate = false;
      this.values = new List<LDValue>();
    }

    public Clause(Object raw) {
      System.assertNotEquals(raw, null);

      Map<String, Object> obj = (Map<String, Object>) raw;

      this.attribute = (String) obj.get('attribute');
      this.operator = (String) obj.get('op');
      this.negate = (Boolean) obj.get('negate');
      this.values = new List<LDValue>();

      List<Object> values = (List<Object>) obj.get('values');

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
    public String ruleId;
    public Boolean trackEvents;
    public List<Clause> clauses;
    public DataModel.VariationOrRollout vor;

    public Rule(String ruleId) {
      this.ruleId = ruleId;
      this.trackEvents = false;
      this.clauses = new List<Clause>();
      this.vor = new VariationOrRollout();
    }

    public Rule(Object raw) {
      System.assertNotEquals(raw, null);

      Map<String, Object> obj = (Map<String, Object>) raw;

      this.ruleId = (String) obj.get('id');
      this.trackEvents = (Boolean) obj.get('trackEvents');
      this.clauses = new List<Clause>();

      List<Object> clauses = (List<Object>) obj.get('clauses');

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
    public Integer variation;
    public List<String> values;

    public Target() {
      this.variation = 0;
      this.values = new List<String>();
    }

    public Target(Object raw) {
      System.assertNotEquals(raw, null);

      Map<String, Object> obj = (Map<String, Object>) raw;

      this.variation = (Integer) obj.get('variation');
      this.values = new List<String>();

      List<Object> values = (List<Object>) obj.get('values');

      System.assertNotEquals(values, null);

      for (Object value : values) {
        this.values.add((String) value);
      }

      System.assertNotEquals(this.variation, null);
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
    private final String key;

    public Prerequisite(Integer variation, String key) {
      this.variation = variation;
      this.key = key;
    }

    public Prerequisite(Object raw) {
      System.assertNotEquals(raw, null);

      Map<String, Object> obj = (Map<String, Object>) raw;

      this.variation = (Integer) obj.get('variation');
      this.key = (String) obj.get('key');

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
    private final String ruleId;
    private final List<Clause> clauses;
    private final Double weight;
    private final String bucketBy;

    public SegmentRule(Object raw) {
      System.assertNotEquals(raw, null);

      Map<String, Object> obj = (Map<String, Object>) raw;

      this.ruleId = (String) obj.get('id');
      this.clauses = new List<Clause>();
      this.weight = (Double) obj.get('weight');
      this.bucketBy = (String) obj.get('bucketBy');

      List<Object> clauses = (List<Object>) obj.get('clauses');

      if (clauses != null) {
        for (Object clause : clauses) {
          this.clauses.add(new DataModel.Clause(clause));
        }
      }

      System.assertNotEquals(this.ruleId, null);
      System.assertNotEquals(this.clauses, null);
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
    public String key;
    public Set<String> included;
    public Set<String> excluded;
    public String salt;
    public List<DataModel.SegmentRule> rules;
    public Integer version;

    public Segment(String key) {
      this.key = key;
      this.included = new Set<String>();
      this.excluded = new Set<String>();
      this.salt = 'abcdefg';
      this.rules = new List<DataModel.SegmentRule>();
      this.version = 0;
    }

    public Segment(Object raw) {
      System.assertNotEquals(raw, null);

      Map<String, Object> obj = (Map<String, Object>) raw;

      this.key = (String) obj.get('key');
      this.included = new Set<String>();
      this.excluded = new Set<String>();
      this.salt = (String) obj.get('salt');
      this.rules = new List<DataModel.SegmentRule>();
      this.version = (Integer) obj.get('version');

      // included
      List<Object> included = (List<Object>) obj.get('included');

      if (included != null) {
        for (Object item : included) {
          this.included.add((String) item);
        }
      }

      // excluded
      List<Object> excluded = (List<Object>) obj.get('excluded');

      if (excluded != null) {
        for (Object item : excluded) {
          this.excluded.add((String) item);
        }
      }

      // rules
      List<Object> rules = (List<Object>) obj.get('rules');

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
    public Integer version;
    public String key;
    public Boolean fieldOn;
    public List<LDValue> variations;
    public Integer offVariation; // may be null
    public DataModel.VariationOrRollout fallthrough;
    public List<DataModel.Target> targets;
    public List<DataModel.Prerequisite> prerequisites;
    public List<DataModel.Rule> rules;
    public String salt;
    public Double debugEventsUntilDate;
    public Boolean trackEvents;
    public Boolean trackEventsFallthrough;

    public Flag() {
      this.fieldOn = false;
      this.offVariation = 0;
      this.variations = new List<LDValue>();
      this.prerequisites = new List<DataModel.Prerequisite>();
      this.targets = new List<DataModel.Target>();
      this.rules = new List<DataModel.Rule>();
      this.fallthrough = new DataModel.VariationOrRollout();
      this.trackEvents = false;
      this.trackEventsFallthrough = false;
      this.version = 0;
    }

    public Flag(String raw) {
      Map<String, Object> obj = (Map<String, Object>) JSON.deserializeUntyped(raw);

      this.version = (Integer) obj.get('version');
      this.key = (String) obj.get('key');
      this.fieldOn = (Boolean) obj.get('on');
      this.variations = new List<LDValue>();
      this.offVariation = (Integer) obj.get('offVariation');
      this.targets = new List<DataModel.Target>();
      this.prerequisites = new List<DataModel.Prerequisite>();
      this.rules = new List<DataModel.Rule>();
      this.salt = (String) obj.get('salt');
      this.debugEventsUntilDate = (Double) obj.get('debugEventsUntilDate');
      this.trackEvents = (Boolean) obj.get('trackEvents');
      this.trackEventsFallthrough = (Boolean) obj.get('trackEventsFallthrough');

      if (this.trackEvents == null) {
        this.trackEvents = false;
      }

      if (this.trackEventsFallthrough == null) {
        this.trackEventsFallthrough = false;
      }

      // variations
      List<Object> variations = (List<Object>) obj.get('variations');

      for (Object variation : variations) {
        this.variations.add(LDValue.ofGeneric(variation));
      }

      // fallthrough
      this.fallthrough = new DataModel.VariationOrRollout((Object) obj.get('fallthrough'));

      // targets
      List<Object> targets = (List<Object>) obj.get('targets');

      if (targets != null) {
        for (Object target : targets) {
          this.targets.add(new DataModel.Target(target));
        }
      }

      // prerequisites
      List<Object> prerequisites = (List<Object>) obj.get('prerequisites');

      if (prerequisites != null) {
        for (Object prerequisite : prerequisites) {
          this.prerequisites.add(new DataModel.Prerequisite(prerequisite));
        }
      }

      // rules
      List<Object> rules = (List<Object>) obj.get('rules');

      if (rules != null) {
        for (Object rule : rules) {
          this.rules.add(new DataModel.Rule(rule));
        }
      }

      System.assertNotEquals(this.version, null);
      System.assertNotEquals(this.key, null);
      System.assertNotEquals(this.fieldOn, null);
      System.assertNotEquals(this.variations, null);
      System.assertNotEquals(this.prerequisites, null);
      System.assertNotEquals(this.rules, null);
      System.assertNotEquals(this.salt, null);
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

    public Double getDebugEventsUntilDate() {
      return this.debugEventsUntilDate;
    }

    public Boolean getTrackEvents() {
      return this.trackEvents;
    }

    public Boolean getTrackEventsFallthrough() {
      return this.trackEventsFallthrough;
    }
  }
}
