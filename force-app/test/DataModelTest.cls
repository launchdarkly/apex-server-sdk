@isTest
private class DataModelTest {
    @isTest static void deserializeTarget() {
        String targetRaw =
            '{' +
                '"variation": 3,' +
                '"values": [' +
                    '"hello"' +
                ']' +
            '}';

        DataModel.Target target = new DataModel.Target(JSON.deserializeUntyped(targetRaw));

        List<String> values = new List<String>();
        values.add('hello');

        System.assertEquals(3, target.getVariation());
        System.assertEquals(values, target.getValues());
    }

    @isTest static void deserializeSegment() {
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

    @isTest static void deserializeClause() {
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

    @isTest static void deserializeRuleWithVariation() {
        String raw =
            '{' +
                '"variation": 2,' +
                '"id": "testid",' +
                '"trackEvents": true,' +
                '"clauses": []' +
            '}';

        DataModel.Rule rule = new DataModel.Rule(JSON.deserializeUntyped(raw));

        System.assertEquals(2, rule.getVariationOrRollout().getVariation());
        System.assertEquals('testid', rule.getId());
        System.assertEquals(true, rule.shouldTrackEvents());
        System.assertEquals(0, rule.getClauses().size());
    }
}