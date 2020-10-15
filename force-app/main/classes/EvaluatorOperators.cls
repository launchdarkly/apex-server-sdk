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
            when 'contains' {
                return userValue.isString() && clauseValue.isString()
                    && userValue.stringValue().contains(clauseValue.stringValue());
            }
            when 'endsWith' {
                return userValue.isString() && clauseValue.isString()
                    && userValue.stringValue().endsWith(clauseValue.stringValue());
            }
            when 'startsWith' {
                return userValue.isString() && clauseValue.isString()
                    && userValue.stringValue().startsWith(clauseValue.stringValue());
            }
            when 'in' {
                return userValue.equals(clauseValue);
            }
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
            when 'matches' {
                return compareRegex(userValue, clauseValue);
            }
            when 'before' {
                return compareDate(ComparisonOp.LT, userValue, clauseValue);
            }
            when 'after' {
                return compareDate(ComparisonOp.GT, userValue, clauseValue);
            }
            when 'semVerEqual' {
                return compareSemanticVersion(ComparisonOp.EQ, userValue, clauseValue);
            }
            when 'semVerGreaterThan' {
                return compareSemanticVersion(ComparisonOp.GT, userValue, clauseValue);
            }
            when 'semVerLessThan' {
                return compareSemanticVersion(ComparisonOp.LT, userValue, clauseValue);
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

        if (clauseValue.getType() != LDValueType.CNUMBER) {
            return false;
        }

        Double n1 = userValue.doubleValue();
        Double n2 = clauseValue.doubleValue();

        return test(op, n1 == n2 ? 0 : (n1 < n2 ? -1 : 1));
    }
    
    private static Boolean compareRegex(LDValue userValue, LDValue clauseValue) {
        if (userValue.getType() != LDValueType.CSTRING) {
            return false;
        }

        if (clauseValue.getType() != LDValueType.CSTRING) {
            return false;
        }

        String s1 = userValue.stringValue();
        String s2 = clauseValue.stringValue();
        
        try {
            Pattern pattern = Pattern.compile(s2);
            
            Matcher matcher = pattern.matcher(s1);
            
            return matcher.find();
        } catch (Exception err) {
            return false;
        }
    }
    
    private static Boolean compareDate(ComparisonOp op, LDValue userValue, LDValue clauseValue) {
        DateTime userDate = valueToDateTime(userValue);

        if (userDate == null) {
            return false;
        }

        DateTime clauseDate = valueToDateTime(clauseValue);

        if (clauseDate == null) {
            return false;
        }

        return test(op, userDate == clauseDate ? 0 : (userDate < clauseDate ? -1 : 1));
    }
    
    private static Boolean compareSemanticVersion(ComparisonOp op, LDValue userValue, LDValue clauseValue) {
        SemanticVersion n1 = valueToSemanticVersion(userValue);

        if (n1 == null) {
            return false;
        }
        
        SemanticVersion n2 = valueToSemanticVersion(clauseValue);

        if (n2 == null) {
            return false;
        }

        return test(op, n1.compare(n2));
    }
    
    private static DateTime valueToDateTime(LDValue value) {
        if (value.isNumber()) {
            return DateTime.newInstance(value.longValue());
        } else if (value.isString()) {
            try {
                return (DateTime)json.deserialize(JSON.serialize(value.stringValue()), DateTime.class);
            } catch (Exception err) {
                return null;
            }
        } else {
            return null;
        }
    }
    
    private static SemanticVersion valueToSemanticVersion(LDValue value) {
        if (value.isString()) {
            return SemanticVersion.parse(value.stringValue());
        } else {
            return null;
        }
    }
}
