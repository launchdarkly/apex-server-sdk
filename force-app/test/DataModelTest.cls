@isTest
private class DataModelTest {
  @isTest
  static void deserializeWeightedVariation() {
    String raw = '{' + '"variation": 31,' + '"weight": 2.5' + '}';

    DataModel.WeightedVariation parsed = DataModel.parseWeightedVariation(JSON.deserializeUntyped(raw));

    System.assertEquals(31, parsed.getVariation());
    System.assertEquals(2.5, parsed.getWeight());
    System.assertEquals(false, parsed.isUntracked());
  }

  @isTest
  static void deserializeWeightedVariationUntracked() {
    String raw = '{' + '"variation": 50,' + '"weight": 3.1,' + '"untracked": true' + '}';

    DataModel.WeightedVariation parsed = DataModel.parseWeightedVariation(JSON.deserializeUntyped(raw));

    System.assertEquals(50, parsed.getVariation());
    System.assertEquals(3.1, parsed.getWeight());
    System.assertEquals(true, parsed.isUntracked());
  }

  @isTest
  static void deserializeRolloutDefaults() {
    String raw = '{}';

    DataModel.Rollout parsed = new DataModel.Rollout(JSON.deserializeUntyped(raw));

    System.assertEquals(null, parsed.getBucketBy());
    System.assertEquals(new List<DataModel.WeightedVariation>(), parsed.getVariations());
    System.assertEquals(DataModel.RolloutKind.ROLLOUT, parsed.getKind());
    System.assertEquals(null, parsed.getSeed());
  }

  @isTest
  static void deserializeRolloutExplicitValues() {
    String raw = '{' + '"bucketBy": "green",' + '"variations": [],' + '"kind": "experiment",' + '"seed": 50' + '}';

    DataModel.Rollout parsed = new DataModel.Rollout(JSON.deserializeUntyped(raw));

    List<DataModel.WeightedVariation> variations = new List<DataModel.WeightedVariation>();

    System.assertEquals('green', parsed.getBucketBy());
    System.assertEquals(variations, parsed.getVariations());
    System.assertEquals(DataModel.RolloutKind.EXPERIMENT, parsed.getKind());
    System.assertEquals(50, parsed.getSeed());
  }

  @isTest
  static void deserializeTarget() {
    String targetRaw = '{' + '"variation": 3,' + '"values": [' + '"hello"' + ']' + '}';

    DataModel.Target target = new DataModel.Target(JSON.deserializeUntyped(targetRaw));

    List<String> values = new List<String>();
    values.add('hello');

    System.assertEquals(3, target.getVariation());
    System.assertEquals(values, target.getValues());
  }

  @isTest
  static void deserializeSegment() {
    String raw =
      '{' +
      '"key": "abc",' +
      '"included": ["red"],' +
      '"excluded": ["blue"],' +
      '"salt": "123",' +
      '"rules": [],' +
      '"version": 3' +
      '}';

    DataModel.Segment segment = new DataModel.Segment(JSON.deserializeUntyped(raw));

    Set<String> included = new Set<String>();
    included.add('red');

    Set<String> excluded = new Set<String>();
    excluded.add('blue');

    System.assertEquals('abc', segment.getKey());
    System.assertEquals('123', segment.getSalt());
    System.assertEquals(3, segment.getVersion());
    System.assertEquals(included, segment.getIncluded());
    System.assertEquals(excluded, segment.getExcluded());
    System.assertEquals(true, segment.getRules().isEmpty());
  }

  @isTest
  static void deserializeClause() {
    String raw =
      '{' +
      '"attribute": "hello",' +
      '"op": "segmentMatch",' +
      '"negate": true,' +
      '"values": [' +
      '"pear"' +
      ']' +
      '}';

    DataModel.Clause clause = new DataModel.Clause(JSON.deserializeUntyped(raw));

    System.assertEquals('hello', clause.getAttribute());
    System.assertEquals('segmentMatch', clause.getOperator());
    System.assertEquals(true, clause.isNegate());
    System.assertEquals(1, clause.getValues().size());
    System.assertEquals('pear', clause.getValues().get(0).stringValue());
  }

  @isTest
  static void deserializeRuleWithVariation() {
    String raw = '{' + '"variation": 2,' + '"id": "testid",' + '"trackEvents": true,' + '"clauses": []' + '}';

    DataModel.Rule rule = new DataModel.Rule(JSON.deserializeUntyped(raw));

    System.assertEquals(2, rule.getVariationOrRollout().getVariation());
    System.assertEquals('testid', rule.getId());
    System.assertEquals(true, rule.shouldTrackEvents());
    System.assertEquals(0, rule.getClauses().size());
  }
}
