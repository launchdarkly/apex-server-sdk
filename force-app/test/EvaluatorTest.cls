@isTest
private class EvaluatorTest {
  public class DataStoreMock implements DataStoreInterface {
    Map<String, DataModel.Flag> flags;
    Map<String, DataModel.Segment> segments;

    public DataStoreMock() {
      this.flags = new Map<String, DataModel.Flag>();
      this.segments = new Map<String, DataModel.Segment>();
    }

    public DataModel.Flag getFlag(String key) {
      return this.flags.get(key);
    }

    public DataModel.Segment getSegment(String key) {
      return this.segments.get(key);
    }

    public Map<String, DataModel.Flag> allFlags() {
      return flags;
    }
  }

  @isTest
  static void offFlagReturnsOffVariation() {
    DataStoreMock store = new DataStoreMock();

    DataModel.Flag flag = new DataModel.Flag();
    flag.fieldOn = false;
    flag.variations.add(LDValue.of(true));

    Evaluator evaluator = new Evaluator(store, new GetTimeMock());

    LDUser user = new LDUser.Builder('abc').build();

    Evaluator.EvalResult result = evaluator.evaluate(flag, user, false);

    System.assertEquals(result.getValue().booleanValue(), true);
    System.assertEquals(result.getVariationIndex(), 0);
    System.assertEquals(result.getReason().getKind(), EvaluationReason.Kind.OFF);
  }

  @isTest
  static void fallthroughEvaluationReturnsFallthrough() {
    DataStoreMock store = new DataStoreMock();

    DataModel.Flag flag = new DataModel.Flag();
    flag.fieldOn = true;
    flag.fallthrough.variation = 0;
    flag.variations.add(LDValue.of(true));

    Evaluator evaluator = new Evaluator(store, new GetTimeMock());

    LDUser user = new LDUser.Builder('abc').build();

    Evaluator.EvalResult result = evaluator.evaluate(flag, user, false);

    System.assertEquals(result.getValue().booleanValue(), true);
    System.assertEquals(result.getVariationIndex(), 0);
    System.assertEquals(result.getReason().getKind(), EvaluationReason.Kind.FALLTHROUGH);
  }

  @isTest
  static void targetMatch() {
    DataStoreMock store = new DataStoreMock();

    DataModel.Flag flag = new DataModel.Flag();
    flag.fieldOn = true;
    flag.fallthrough.variation = 0;
    flag.variations.add(LDValue.of(true));

    DataModel.Target target = new DataModel.Target();
    target.values.add('abc');
    flag.targets.add(target);

    Evaluator evaluator = new Evaluator(store, new GetTimeMock());

    LDUser user = new LDUser.Builder('abc').build();

    Evaluator.EvalResult result = evaluator.evaluate(flag, user, false);

    System.assertEquals(result.getValue().booleanValue(), true);
    System.assertEquals(result.getVariationIndex(), 0);
    System.assertEquals(result.getReason().getKind(), EvaluationReason.Kind.TARGET_MATCH);
  }

  @isTest
  static void targetNotMatch() {
    DataStoreMock store = new DataStoreMock();

    DataModel.Flag flag = new DataModel.Flag();
    flag.fieldOn = true;
    flag.fallthrough.variation = 0;
    flag.variations.add(LDValue.of(true));

    DataModel.Target target = new DataModel.Target();
    target.values.add('abc1');
    flag.targets.add(target);

    Evaluator evaluator = new Evaluator(store, new GetTimeMock());

    LDUser user = new LDUser.Builder('abc').build();

    Evaluator.EvalResult result = evaluator.evaluate(flag, user, false);

    System.assertEquals(result.getValue().booleanValue(), true);
    System.assertEquals(result.getVariationIndex(), 0);
    System.assertEquals(result.getReason().getKind(), EvaluationReason.Kind.FALLTHROUGH);
  }

  @isTest
  static void prereqMatch() {
    DataStoreMock store = new DataStoreMock();

    DataModel.Flag flag = new DataModel.Flag();
    flag.fieldOn = true;
    flag.variations.add(LDValue.of(true));
    flag.fallthrough.variation = 0;

    flag.prerequisites.add(new DataModel.Prerequisite(0, 'other'));

    DataModel.Flag flagSub = new DataModel.Flag();
    flagSub.fieldOn = true;
    flagSub.fallthrough.variation = 0;
    flagSub.variations.add(LDValue.of(true));

    store.flags.put('other', flagSub);

    Evaluator evaluator = new Evaluator(store, new GetTimeMock());

    LDUser user = new LDUser.Builder('abc').build();

    Evaluator.EvalResult result = evaluator.evaluate(flag, user, false);

    System.assertEquals(result.getValue().booleanValue(), true);
    System.assertEquals(result.getVariationIndex(), 0);
    System.assertEquals(result.getReason().getKind(), EvaluationReason.Kind.FALLTHROUGH);
  }

  @isTest
  static void prereqFailed() {
    DataStoreMock store = new DataStoreMock();

    DataModel.Flag flag = new DataModel.Flag();
    flag.fieldOn = true;
    flag.variations.add(LDValue.of(true));
    flag.fallthrough.variation = 0;

    flag.prerequisites.add(new DataModel.Prerequisite(0, 'other'));

    DataModel.Flag flagSub = new DataModel.Flag();
    flagSub.fieldOn = true;
    flagSub.fallthrough.variation = 1;
    flagSub.variations.add(LDValue.of(true));
    flagSub.variations.add(LDValue.of(false));

    store.flags.put('other', flagSub);

    Evaluator evaluator = new Evaluator(store, new GetTimeMock());

    LDUser user = new LDUser.Builder('abc').build();

    Evaluator.EvalResult result = evaluator.evaluate(flag, user, false);

    System.assertEquals(result.getValue().booleanValue(), true);
    System.assertEquals(result.getVariationIndex(), 0);
    System.assertEquals(result.getReason().getKind(), EvaluationReason.Kind.PREREQUISITE_FAILED);
  }

  @isTest
  static void segmentIncludedUser() {
    DataStoreMock store = new DataStoreMock();

    DataModel.Clause clause = new DataModel.Clause('key', 'segmentMatch');
    clause.values.add(LDValue.of('segment-a'));

    DataModel.Rule rule = new DataModel.Rule('rule');
    rule.clauses.add(clause);
    rule.vor.variation = 2;

    DataModel.Flag flag = new DataModel.Flag();
    flag.fieldOn = true;
    flag.variations.add(LDValue.of('bad'));
    flag.variations.add(LDValue.of('fallthrough'));
    flag.variations.add(LDValue.of('expected'));
    flag.rules.add(rule);
    flag.fallthrough.variation = 1;

    DataModel.Segment segment = new DataModel.Segment('segment-a');
    segment.included.add('abc');

    store.segments.put('segment-a', segment);

    Evaluator evaluator = new Evaluator(store, new GetTimeMock());

    LDUser user = new LDUser.Builder('abc').build();

    Evaluator.EvalResult result = evaluator.evaluate(flag, user, false);

    System.assertEquals(result.getValue().equals(LDValue.of('expected')), true);
    System.assertEquals(result.getVariationIndex(), 2);
    System.assertEquals(result.getReason().getKind(), EvaluationReason.Kind.RULE_MATCH);
  }

  @isTest
  static void segmentExcludedUser() {
    DataStoreMock store = new DataStoreMock();

    DataModel.Clause clause = new DataModel.Clause('key', 'segmentMatch');
    clause.values.add(LDValue.of('segment-a'));

    DataModel.Rule rule = new DataModel.Rule('rule');
    rule.clauses.add(clause);
    rule.vor.variation = 2;

    DataModel.Flag flag = new DataModel.Flag();
    flag.fieldOn = true;
    flag.variations.add(LDValue.of('bad'));
    flag.variations.add(LDValue.of('fallthrough'));
    flag.variations.add(LDValue.of('unexpected'));
    flag.rules.add(rule);
    flag.fallthrough.variation = 1;

    DataModel.Segment segment = new DataModel.Segment('segment-a');
    segment.excluded.add('abc');

    store.segments.put('segment-a', segment);

    Evaluator evaluator = new Evaluator(store, new GetTimeMock());

    LDUser user = new LDUser.Builder('abc').build();

    Evaluator.EvalResult result = evaluator.evaluate(flag, user, false);

    System.assertEquals(result.getValue().equals(LDValue.of('fallthrough')), true);
    System.assertEquals(result.getVariationIndex(), 1);
    System.assertEquals(result.getReason().getKind(), EvaluationReason.Kind.FALLTHROUGH);
  }

  @isTest
  static void bucketUser() {
    DataStoreMock store = new DataStoreMock();
    Evaluator evaluator = new Evaluator(store, new GetTimeMock());

    Double v1 = evaluator.bucketUser(new LDUser.Builder('userKeyA').build(), 'hashKey', 'key', 'saltyA', null);
    System.assertEquals(v1, (Double) 0.42157587);

    Double v2 = evaluator.bucketUser(new LDUser.Builder('userKeyB').build(), 'hashKey', 'key', 'saltyA', null);
    System.assertEquals(v2, (Double) 0.6708485);

    Double v3 = evaluator.bucketUser(new LDUser.Builder('userKeyC').build(), 'hashKey', 'key', 'saltyA', null);
    System.assertEquals(v3, (Double) 0.10343106);
  }

  @isTest
  static void bucketUserWithSeed() {
    DataStoreMock store = new DataStoreMock();
    Evaluator evaluator = new Evaluator(store, new GetTimeMock());

    Double v1 = evaluator.bucketUser(new LDUser.Builder('userKeyA').build(), 'hashKey', 'key', 'saltyA', 61);
    System.assertEquals(v1, (Double) 0.09801207);

    Double v2 = evaluator.bucketUser(new LDUser.Builder('userKeyB').build(), 'hashKey', 'key', 'saltyA', 61);
    System.assertEquals(v2, (Double) 0.14483777);

    Double v3 = evaluator.bucketUser(new LDUser.Builder('userKeyC').build(), 'hashKey', 'key', 'saltyA', 61);
    System.assertEquals(v3, (Double) 0.92426409);
  }

  @isTest
  static void variationIndexForUser() {
    DataStoreMock store = new DataStoreMock();
    Evaluator evaluator = new Evaluator(store, new GetTimeMock());

    DataModel.VariationOrRollout vor = new DataModel.VariationOrRollout();
    DataModel.Rollout rollout = new DataModel.Rollout();
    vor.rollout = rollout;
    rollout.kind = DataModel.RolloutKind.EXPERIMENT;
    rollout.variations = new List<DataModel.WeightedVariation>();

    rollout.variations.add(new DataModel.WeightedVariation(0, 60000, true));
    rollout.variations.add(new DataModel.WeightedVariation(1, 40000, false));

    Evaluator.VariationIndexForUserResult v1 = evaluator.variationIndexForUser(
      vor,
      new LDUser.Builder('userKeyA').build(),
      'hashKey',
      'saltyA'
    );
    System.assertEquals(0, v1.variationIndex);
    System.assertEquals(false, v1.inExperiment);

    Evaluator.VariationIndexForUserResult v2 = evaluator.variationIndexForUser(
      vor,
      new LDUser.Builder('userKeyB').build(),
      'hashKey',
      'saltyA'
    );
    System.assertEquals(1, v2.variationIndex);
    System.assertEquals(true, v2.inExperiment);

    Evaluator.VariationIndexForUserResult v3 = evaluator.variationIndexForUser(
      vor,
      new LDUser.Builder('userKeyC').build(),
      'hashKey',
      'saltyA'
    );
    System.assertEquals(0, v3.variationIndex);
    System.assertEquals(false, v3.inExperiment);
  }
}
