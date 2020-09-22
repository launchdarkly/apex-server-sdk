@isTest
private class EvaluatorOperatorTest {
    @isTest static void unknownOperator() {
        System.assertEquals(EvaluatorOperators.apply('unknown', null, null), false);
    }

    @isTest static void lessThan() {
        System.assertEquals(EvaluatorOperators.apply('lessThan', LDValue.of(2), LDValue.of(3)), true);
        System.assertEquals(EvaluatorOperators.apply('lessThan', LDValue.of(3), LDValue.of(2)), false);
    }
}
