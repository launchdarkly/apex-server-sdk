public class EvaluatorOperators {
    private enum ComparisonOp {
        EQ,
        LT,
        LTE,
        GT,
        GTE
    }

    private static Boolean test(ComparisonOp op, Integer delta) {
        switch on op {
            when EQ {
              return delta == 0;
            }
            when LT {
              return delta < 0;
            }
            when LTE {
              return delta <= 0;
            }
            when GT {
              return delta > 0;
            }
            when GTE {
              return delta >= 0;
            }
            when else {
                return false;
            }
        }
    }

    public static Boolean apply(String op, LDValue userValue, LDValue clauseValue) {
        switch on op {
            when 'lessThan' {
                return compareNumeric(ComparisonOp.LT, userValue, clauseValue);
            }
            when 'lessThanOrEqual' {
                return compareNumeric(ComparisonOp.LTE, userValue, clauseValue);
            }
            when 'greaterThan' {
                return compareNumeric(ComparisonOp.GT, userValue, clauseValue);
            }
            when 'greaterThanOrEqual' {
                return compareNumeric(ComparisonOp.GTE, userValue, clauseValue);
            }
            when else {
                return false;
            }
        }
    }

    private static Boolean compareNumeric(ComparisonOp op, LDValue userValue, LDValue clauseValue) {
        if (userValue.getType() != LDValueType.CNUMBER) {
            return false;
        }

        if (userValue.getType() != LDValueType.CNUMBER) {
            return false;
        }

        Double n1 = userValue.doubleValue();
        Double n2 = clauseValue.doubleValue();

        return test(op, n1 == n2 ? 0 : (n1 < n2 ? -1 : 1));
    }
}
