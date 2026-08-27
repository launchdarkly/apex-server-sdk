@isTest
private class EvaluatorOperatorTest {
  @isTest
  static void unknownOperator() {
    System.assertEquals(EvaluatorOperators.apply('unknown', null, null), false);
  }

  @isTest
  static void numericComparison() {
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

  @isTest
  static void stringComparison() {
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
    System.assertEquals(
      EvaluatorOperators.apply('contains', LDValue.of('that 2 is not a string'), LDValue.of(2)),
      false
    );
  }

  @isTest
  static void mixedStringNumberComparison() {
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

  @isTest
  static void booleanComparison() {
    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(true), LDValue.of(true)), true);
    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(false), LDValue.of(false)), true);
    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(true), LDValue.of(false)), false);
    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(false), LDValue.of(true)), false);
  }

  @isTest
  static void regexComparison() {
    System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('hello.*rld')), true);
    System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('hello.*orl')), true);
    System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('l+')), true);
    System.assertEquals(
      EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('(world|planet)')),
      true
    );
    System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('aloha')), false);
    System.assertEquals(
      EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('***not a regex')),
      false
    );
    System.assertEquals(
      EvaluatorOperators.apply('matches', LDValue.of(2), LDValue.of('that 2 is not a string')),
      false
    );
  }

  private static final LDValue dateStr1 = LDValue.of('2017-12-06T00:00:00.000-07:00');
  private static final LDValue dateStr2 = LDValue.of('2017-12-06T00:01:01.000-07:00');
  private static final LDValue dateStrUtc1 = LDValue.of('2017-12-06T00:00:00.000Z');
  private static final LDValue dateStrUtc2 = LDValue.of('2017-12-06T00:01:01.000Z');
  private static final LDValue dateMs1 = LDValue.of(10000000);
  private static final LDValue dateMs2 = LDValue.of(10000001);
  private static final LDValue invalidDate = LDValue.of('hey what\'s this?');
  private static final LDValue invalidVer = LDValue.of('xbad%ver');

  @isTest
  static void dateComparison() {
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

  @isTest
  static void semVerComparison() {
    System.assertEquals(EvaluatorOperators.apply('semVerEqual', LDValue.of('2.0.1'), LDValue.of('2.0.1')), true);
    System.assertEquals(EvaluatorOperators.apply('semVerEqual', LDValue.of('2.0.2'), LDValue.of('2.0.1')), false);
    System.assertEquals(EvaluatorOperators.apply('semVerEqual', LDValue.of('2.0'), LDValue.of('2.0.0')), true);
    System.assertEquals(EvaluatorOperators.apply('semVerEqual', LDValue.of('2'), LDValue.of('2.0.0')), true);
    System.assertEquals(EvaluatorOperators.apply('semVerEqual', LDValue.of('2-rc1'), LDValue.of('2.0.0-rc1')), true);
    System.assertEquals(
      EvaluatorOperators.apply('semVerEqual', LDValue.of('2+build1'), LDValue.of('2.0.0+build1')),
      true
    );
    System.assertEquals(EvaluatorOperators.apply('semVerEqual', LDValue.of('abc'), LDValue.of('2.0.1')), false);
    System.assertEquals(EvaluatorOperators.apply('semVerEqual', LDValue.of(2), LDValue.of('2.0.1')), false);
    System.assertEquals(EvaluatorOperators.apply('semVerEqual', LDValue.of('2.0.1'), LDValue.of('abc')), false);
    System.assertEquals(EvaluatorOperators.apply('semVerEqual', LDValue.of('2.0.1'), LDValue.of(2)), false);

    System.assertEquals(EvaluatorOperators.apply('semVerLessThan', LDValue.of('2.0.0'), LDValue.of('2.0.1')), true);
    System.assertEquals(EvaluatorOperators.apply('semVerLessThan', LDValue.of('2.0'), LDValue.of('2.0.1')), true);
    System.assertEquals(EvaluatorOperators.apply('semVerLessThan', LDValue.of('2.0.1'), LDValue.of('2.0.0')), false);
    System.assertEquals(EvaluatorOperators.apply('semVerLessThan', LDValue.of('2.0.1'), LDValue.of('2')), false);
    System.assertEquals(EvaluatorOperators.apply('semVerLessThan', LDValue.of('2.0.0-rc'), LDValue.of('2.0.0')), true);
    System.assertEquals(
      EvaluatorOperators.apply('semVerLessThan', LDValue.of('2.0.0-rc'), LDValue.of('2.0.0-rc.beta')),
      true
    );
    System.assertEquals(EvaluatorOperators.apply('semVerLessThan', LDValue.of('2.0.1'), invalidVer), false);

    System.assertEquals(EvaluatorOperators.apply('semVerGreaterThan', LDValue.of('2.0.1'), LDValue.of('2.0.0')), true);
    System.assertEquals(EvaluatorOperators.apply('semVerGreaterThan', LDValue.of('2.0.1'), LDValue.of('2.0')), true);
    System.assertEquals(EvaluatorOperators.apply('semVerGreaterThan', LDValue.of('2.0.0'), LDValue.of('2.0.1')), false);
    System.assertEquals(EvaluatorOperators.apply('semVerGreaterThan', LDValue.of('2.0'), LDValue.of('2.0.1')), false);
    System.assertEquals(
      EvaluatorOperators.apply('semVerGreaterThan', LDValue.of('2.0.0-rc.1'), LDValue.of('2.0.0-rc.0')),
      true
    );
    System.assertEquals(EvaluatorOperators.apply('semVerGreaterThan', LDValue.of('2.0.1'), invalidVer), false);
  }

  @isTest
  static void inIsCaseSensitiveForStrings() {
    LDValue userEmail = LDValue.of('bob@example.com');

    System.assertEquals(EvaluatorOperators.apply('in', userEmail, LDValue.of('bob@example.com')), true);
    System.assertEquals(EvaluatorOperators.apply('in', userEmail, LDValue.of('Bob@Example.COM')), false);
    System.assertEquals(EvaluatorOperators.apply('in', userEmail, LDValue.of('BOB@EXAMPLE.COM')), false);
    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of('Bob@Example.COM'), userEmail), false);

    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of('x'), LDValue.of('x')), true);
    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of('x'), LDValue.of('X')), false);
    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of('X'), LDValue.of('x')), false);
  }

  @isTest
  static void inIsCaseSensitiveInsideArrays() {
    LDValue lower = new LDValueArray.Builder().add(LDValue.of('bob')).add(LDValue.of(1)).build();
    LDValue sameCase = new LDValueArray.Builder().add(LDValue.of('bob')).add(LDValue.of(1)).build();
    LDValue upper = new LDValueArray.Builder().add(LDValue.of('Bob')).add(LDValue.of(1)).build();
    LDValue nestedLower = new LDValueArray.Builder().add(lower).build();
    LDValue nestedSameCase = new LDValueArray.Builder().add(sameCase).build();
    LDValue nestedUpper = new LDValueArray.Builder().add(upper).build();

    System.assertEquals(EvaluatorOperators.apply('in', lower, sameCase), true);
    System.assertEquals(EvaluatorOperators.apply('in', lower, upper), false);
    System.assertEquals(EvaluatorOperators.apply('in', upper, lower), false);

    System.assertEquals(EvaluatorOperators.apply('in', nestedLower, nestedSameCase), true);
    System.assertEquals(EvaluatorOperators.apply('in', nestedLower, nestedUpper), false);
    System.assertEquals(EvaluatorOperators.apply('in', nestedUpper, nestedLower), false);
  }

  @isTest
  static void inIsCaseSensitiveInsideObjects() {
    LDValue lower = new LDValueObject.Builder().set('email', LDValue.of('bob')).build();
    LDValue sameCase = new LDValueObject.Builder().set('email', LDValue.of('bob')).build();
    LDValue upperValue = new LDValueObject.Builder().set('email', LDValue.of('Bob')).build();
    LDValue upperKey = new LDValueObject.Builder().set('EMAIL', LDValue.of('bob')).build();
    LDValue nestedLower = new LDValueObject.Builder().set('user', lower).build();
    LDValue nestedSameCase = new LDValueObject.Builder().set('user', sameCase).build();
    LDValue nestedUpper = new LDValueObject.Builder().set('user', upperValue).build();

    System.assertEquals(EvaluatorOperators.apply('in', lower, sameCase), true);
    System.assertEquals(EvaluatorOperators.apply('in', lower, upperValue), false);
    System.assertEquals(EvaluatorOperators.apply('in', upperValue, lower), false);
    System.assertEquals(EvaluatorOperators.apply('in', lower, upperKey), false);

    System.assertEquals(EvaluatorOperators.apply('in', nestedLower, nestedSameCase), true);
    System.assertEquals(EvaluatorOperators.apply('in', nestedLower, nestedUpper), false);
    System.assertEquals(EvaluatorOperators.apply('in', nestedUpper, nestedLower), false);
  }

  @isTest
  static void inComparesNonStringTypes() {
    LDValue emptyArray = new LDValueArray.Builder().build();
    LDValue otherEmptyArray = new LDValueArray.Builder().build();
    LDValue emptyObject = new LDValueObject.Builder().build();
    LDValue otherEmptyObject = new LDValueObject.Builder().build();
    LDValue oneItemArray = new LDValueArray.Builder().add(LDValue.of('a')).build();
    LDValue twoItemArray = new LDValueArray.Builder().add(LDValue.of('a')).add(LDValue.of('b')).build();
    LDValue oneKeyObject = new LDValueObject.Builder().set('a', LDValue.of('a')).build();

    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(true), LDValue.of(true)), true);
    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(true), LDValue.of(false)), false);

    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(7), LDValue.of(7)), true);
    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(7), LDValue.of(7.5)), false);

    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(''), LDValue.of('')), true);
    System.assertEquals(EvaluatorOperators.apply('in', emptyArray, otherEmptyArray), true);
    System.assertEquals(EvaluatorOperators.apply('in', emptyObject, otherEmptyObject), true);

    System.assertEquals(EvaluatorOperators.apply('in', oneItemArray, twoItemArray), false);
    System.assertEquals(EvaluatorOperators.apply('in', oneItemArray, oneKeyObject), false);
    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of(true), LDValue.of(1)), false);
    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of('x'), LDValue.of(true)), false);
    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of('x'), oneItemArray), false);
  }

  @isTest
  static void containsIsCaseSensitive() {
    System.assertEquals(EvaluatorOperators.apply('contains', LDValue.of('hello world'), LDValue.of('lo wo')), true);
    System.assertEquals(EvaluatorOperators.apply('contains', LDValue.of('hello world'), LDValue.of('LO WO')), false);
    System.assertEquals(EvaluatorOperators.apply('contains', LDValue.of('HELLO WORLD'), LDValue.of('lo wo')), false);
  }

  @isTest
  static void startsWithIsCaseSensitive() {
    System.assertEquals(EvaluatorOperators.apply('startsWith', LDValue.of('hello world'), LDValue.of('hello')), true);
    System.assertEquals(EvaluatorOperators.apply('startsWith', LDValue.of('hello world'), LDValue.of('Hello')), false);
    System.assertEquals(EvaluatorOperators.apply('startsWith', LDValue.of('Hello world'), LDValue.of('hello')), false);
  }

  @isTest
  static void endsWithIsCaseSensitive() {
    System.assertEquals(EvaluatorOperators.apply('endsWith', LDValue.of('hello world'), LDValue.of('world')), true);
    System.assertEquals(EvaluatorOperators.apply('endsWith', LDValue.of('hello world'), LDValue.of('World')), false);
    System.assertEquals(EvaluatorOperators.apply('endsWith', LDValue.of('hello worlD'), LDValue.of('world')), false);
  }

  @isTest
  static void matchesIsCaseSensitive() {
    System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('hello')), true);
    System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('Hello')), false);
    System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('HELLO'), LDValue.of('HELLO')), true);
    System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('HELLO'), LDValue.of('hello')), false);
    System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('hello world'), LDValue.of('[A-Z]+')), false);
  }

  @isTest
  static void semVerIsCaseSensitiveInPrerelease() {
    LDValue lowerVer = LDValue.of('1.0.0-alpha');
    LDValue upperVer = LDValue.of('1.0.0-ALPHA');

    System.assertEquals(EvaluatorOperators.apply('semVerEqual', lowerVer, LDValue.of('1.0.0-alpha')), true);
    System.assertEquals(EvaluatorOperators.apply('semVerEqual', lowerVer, upperVer), false);
    System.assertEquals(EvaluatorOperators.apply('semVerEqual', upperVer, lowerVer), false);

    System.assertEquals(EvaluatorOperators.apply('semVerGreaterThan', lowerVer, upperVer), true);
    System.assertEquals(EvaluatorOperators.apply('semVerGreaterThan', upperVer, lowerVer), false);

    System.assertEquals(EvaluatorOperators.apply('semVerLessThan', upperVer, lowerVer), true);
    System.assertEquals(EvaluatorOperators.apply('semVerLessThan', lowerVer, upperVer), false);
  }

  @isTest
  static void everyOperatorRejectsTypeMismatch() {
    LDValue boolValue = LDValue.of(true);
    LDValue arrayValue = new LDValueArray.Builder().add(LDValue.of('a')).build();
    LDValue objectValue = new LDValueObject.Builder().set('a', LDValue.of('a')).build();

    System.assertEquals(EvaluatorOperators.apply('in', LDValue.of('x'), boolValue), false);
    System.assertEquals(EvaluatorOperators.apply('contains', boolValue, LDValue.of('x')), false);
    System.assertEquals(EvaluatorOperators.apply('startsWith', LDValue.of('x'), boolValue), false);
    System.assertEquals(EvaluatorOperators.apply('endsWith', arrayValue, LDValue.of('a')), false);
    System.assertEquals(EvaluatorOperators.apply('matches', LDValue.of('x'), boolValue), false);
    System.assertEquals(EvaluatorOperators.apply('lessThan', LDValue.of('1'), LDValue.of(2)), false);
    System.assertEquals(EvaluatorOperators.apply('lessThanOrEqual', objectValue, LDValue.of(2)), false);
    System.assertEquals(EvaluatorOperators.apply('greaterThan', boolValue, LDValue.of(2)), false);
    System.assertEquals(EvaluatorOperators.apply('greaterThanOrEqual', LDValue.of(2), arrayValue), false);
    System.assertEquals(EvaluatorOperators.apply('before', boolValue, LDValue.of(1)), false);
    System.assertEquals(EvaluatorOperators.apply('after', LDValue.of(1), boolValue), false);
    System.assertEquals(EvaluatorOperators.apply('semVerEqual', boolValue, LDValue.of('1.0.0')), false);
    System.assertEquals(EvaluatorOperators.apply('semVerGreaterThan', LDValue.of('1.0.1'), arrayValue), false);
    System.assertEquals(EvaluatorOperators.apply('semVerLessThan', objectValue, LDValue.of('1.0.1')), false);
  }

  @isTest
  static void operatorNameIsCaseSensitive() {
    System.assertEquals(EvaluatorOperators.apply('IN', LDValue.of('x'), LDValue.of('x')), false);
    System.assertEquals(EvaluatorOperators.apply('In', LDValue.of('x'), LDValue.of('x')), false);
    System.assertEquals(EvaluatorOperators.apply('Contains', LDValue.of('xyz'), LDValue.of('y')), false);
    System.assertEquals(EvaluatorOperators.apply('STARTSWITH', LDValue.of('xyz'), LDValue.of('x')), false);
    System.assertEquals(EvaluatorOperators.apply('EndsWith', LDValue.of('xyz'), LDValue.of('z')), false);
    System.assertEquals(EvaluatorOperators.apply('Matches', LDValue.of('xyz'), LDValue.of('x')), false);
    System.assertEquals(EvaluatorOperators.apply('LessThan', LDValue.of(1), LDValue.of(2)), false);
    System.assertEquals(EvaluatorOperators.apply('Before', LDValue.of(1), LDValue.of(2)), false);
    System.assertEquals(EvaluatorOperators.apply('After', LDValue.of(2), LDValue.of(1)), false);
    System.assertEquals(EvaluatorOperators.apply('SemVerEqual', LDValue.of('2.0.0'), LDValue.of('2.0.0')), false);
  }

  @isTest
  static void unknownOperatorWithValues() {
    System.assertEquals(EvaluatorOperators.apply('unknown', LDValue.of('x'), LDValue.of('x')), false);
    System.assertEquals(EvaluatorOperators.apply('', LDValue.of('x'), LDValue.of('x')), false);
    System.assertEquals(EvaluatorOperators.apply('in ', LDValue.of('x'), LDValue.of('x')), false);
    System.assertEquals(EvaluatorOperators.apply('segmentMatch', LDValue.of('x'), LDValue.of('x')), false);
  }
}
