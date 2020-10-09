@isTest
private class EvaluatorOperatorTest {
    @isTest static void unknownOperator() {
        System.assertEquals(EvaluatorOperators.apply('unknown', null, null), false);
    }

    @isTest static void numericComparison() {
        System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(99), LDValue.of(99)), true);
        System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(99.0001), LDValue.of(99.0001)), true);
        System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(99), LDValue.of(99.0001)), false);
        System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(99.0001), LDValue.of(99)), false);

        System.assertEquals(EvaluatorOperators.apply('lessThan', LDValue.of(99), LDValue.of(99.0001)), true);
        System.assertEquals(EvaluatorOperators.apply('lessThan', LDValue.of(99.0001), LDValue.of(99)), false);
        System.assertEquals(EvaluatorOperators.apply('lessThan', LDValue.of(99), LDValue.of(99)), false);

        System.assertEquals(EvaluatorOperators.apply('lessThanOrEqual', LDValue.of(99), LDValue.of(99.0001)), true);
        System.assertEquals(EvaluatorOperators.apply('lessThanOrEqual', LDValue.of(99.0001), LDValue.of(99)), false);
        System.assertEquals(EvaluatorOperators.apply('lessThanOrEqual', LDValue.of(99), LDValue.of(99)), true);

        System.assertEquals(EvaluatorOperators.apply('greaterThan', LDValue.of(99.0001), LDValue.of(99)), true);
        System.assertEquals(EvaluatorOperators.apply('greaterThan', LDValue.of(99), LDValue.of(99.0001)), false);
        System.assertEquals(EvaluatorOperators.apply('greaterThan', LDValue.of(99), LDValue.of(99)), false);

        System.assertEquals(EvaluatorOperators.apply('greaterThanOrEqual', LDValue.of(99.0001), LDValue.of(99)), true);
        System.assertEquals(EvaluatorOperators.apply('greaterThanOrEqual', LDValue.of(99), LDValue.of(99.0001)), false);
        System.assertEquals(EvaluatorOperators.apply('greaterThanOrEqual', LDValue.of(99), LDValue.of(99)), true);
    }

    @isTest static void stringComparison() {
        System.assertEquals(EvaluatorOperators.apply('in', LDValue.of('x'), LDValue.of('x')), true);
        System.assertEquals(EvaluatorOperators.apply('in', LDValue.of('x'), LDValue.of('xyz')), false);

        System.assertEquals(EvaluatorOperators.apply('startsWith', LDValue.of('xyz'), LDValue.of('x')), true);
        System.assertEquals(EvaluatorOperators.apply('startsWith', LDValue.of('x'), LDValue.of('xyz')), false);
        System.assertEquals(EvaluatorOperators.apply('startsWith', LDValue.of(1), LDValue.of('xyz')), false);
        System.assertEquals(EvaluatorOperators.apply('startsWith', LDValue.of('1xyz'), LDValue.of(1)), false);
        
        System.assertEquals(EvaluatorOperators.apply('endsWith', LDValue.of('xyz'), LDValue.of('z')), true);
        System.assertEquals(EvaluatorOperators.apply('endsWith', LDValue.of('z'), LDValue.of('xyz')), false);
        System.assertEquals(EvaluatorOperators.apply('endsWith', LDValue.of(1), LDValue.of('xyz')), false);
        System.assertEquals(EvaluatorOperators.apply('endsWith', LDValue.of('1xyz'), LDValue.of(1)), false);

        System.assertEquals(EvaluatorOperators.apply('contains', LDValue.of('xyz'), LDValue.of('y')), true);
        System.assertEquals(EvaluatorOperators.apply('contains', LDValue.of('y'), LDValue.of('xyz')), false);
        System.assertEquals(EvaluatorOperators.apply('contains', LDValue.of(2), LDValue.of('xyz')), false);
        System.assertEquals(EvaluatorOperators.apply('contains', LDValue.of('that 2 is not a string'), LDValue.of(2)), false);
    }

    @isTest static void mixedStringNumberComparison() {
        System.assertEquals(EvaluatorOperators.apply('in', LDValue.of('99'), LDValue.of(99)), false);
        System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(99), LDValue.of('99')), false);

        System.assertEquals(EvaluatorOperators.apply('contains', LDValue.of('99'), LDValue.of(99)), false);

        System.assertEquals(EvaluatorOperators.apply('startsWith', LDValue.of('99'), LDValue.of(99)), false);

        System.assertEquals(EvaluatorOperators.apply('endsWith', LDValue.of('99'), LDValue.of(99)), false);

        System.assertEquals(EvaluatorOperators.apply('lessThanOrEqual', LDValue.of('99'), LDValue.of(99)), false);
        System.assertEquals(EvaluatorOperators.apply('lessThanOrEqual', LDValue.of(99), LDValue.of('99')), false);

        System.assertEquals(EvaluatorOperators.apply('greaterThanOrEqual', LDValue.of('99'), LDValue.of(99)), false);
        System.assertEquals(EvaluatorOperators.apply('greaterThanOrEqual', LDValue.of(99), LDValue.of('99')), false);
    }

    @isTest static void booleanComparison() {
        System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(true), LDValue.of(true)), true);
        System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(false), LDValue.of(false)), true);
        System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(true), LDValue.of(false)), false);
        System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(false), LDValue.of(true)), false);
    }

    @isTest static void regexComparison() {
        System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('hello.*rld')), true);
        System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('hello.*orl')), true);
        System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('l+')), true);
        System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('(world|planet)')), true);
        System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('aloha')), false);
        System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('***not a regex')), false);
        System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of(2), LDValue.of('that 2 is not a string')), false);
    }

    private static final LDValue dateStr1 = LDValue.of('2017-12-06T00:00:00.000-07:00');
    private static final LDValue dateStr2 = LDValue.of('2017-12-06T00:01:01.000-07:00');
    private static final LDValue dateStrUtc1 = LDValue.of('2017-12-06T00:00:00.000Z');
    private static final LDValue dateStrUtc2 = LDValue.of('2017-12-06T00:01:01.000Z');
    private static final LDValue dateMs1 = LDValue.of(10000000);
    private static final LDValue dateMs2 = LDValue.of(10000001);
    private static final LDValue invalidDate = LDValue.of('hey what\'s this?');

    @isTest static void dateComparison() {
        System.assertEquals(EvaluatorOperators.apply('before', dateStr1, dateStr2), true);
        System.assertEquals(EvaluatorOperators.apply('before', dateStrUtc1, dateStrUtc2), true);
        System.assertEquals(EvaluatorOperators.apply('before', dateMs1, dateMs2), true);
        System.assertEquals(EvaluatorOperators.apply('before', dateStr2, dateStr1), false);
        System.assertEquals(EvaluatorOperators.apply('before', dateStrUtc2, dateStrUtc1), false);
        System.assertEquals(EvaluatorOperators.apply('before', dateMs2, dateMs1), false);
        System.assertEquals(EvaluatorOperators.apply('before', dateStr1, dateStr1), false);
        System.assertEquals(EvaluatorOperators.apply('before', dateMs1, dateMs1), false);
        System.assertEquals(EvaluatorOperators.apply('before', dateStr1, invalidDate), false);
        System.assertEquals(EvaluatorOperators.apply('before', invalidDate, dateStr1), false);
        
        System.assertEquals(EvaluatorOperators.apply('after', dateStr1, dateStr2), false);
        System.assertEquals(EvaluatorOperators.apply('after', dateStrUtc1, dateStrUtc2), false);
        System.assertEquals(EvaluatorOperators.apply('after', dateMs1, dateMs2), false);
        System.assertEquals(EvaluatorOperators.apply('after', dateStr2, dateStr1), true);
        System.assertEquals(EvaluatorOperators.apply('after', dateStrUtc2, dateStrUtc1), true);
        System.assertEquals(EvaluatorOperators.apply('after', dateMs2, dateMs1), true);
        System.assertEquals(EvaluatorOperators.apply('after', dateStr1, dateStr1), false);
        System.assertEquals(EvaluatorOperators.apply('after', dateMs1, dateMs1), false);
        System.assertEquals(EvaluatorOperators.apply('after', dateStr1, invalidDate), false);
        System.assertEquals(EvaluatorOperators.apply('after', invalidDate, dateStr1), false);
    }
}
