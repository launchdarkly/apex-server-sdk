public class EvaluationReason {
    public enum Kind {
        OFF,
        FALLTHROUGH,
        TARGET_MATCH,
        RULE_MATCH,
        PREREQUISITE_FAILED,
        ERROR
    }

    public enum ErrorKind {
        CLIENT_NOT_READY,
        FLAG_NOT_FOUND,
        MALFORMED_FLAG,
        USER_NOT_SPECIFIED,
        WRONG_TYPE,
        EXCEPTION_THROWN
    }

    private final Kind      kind;
    private final Integer   ruleIndex;
    private final String    ruleId;
    private final String    prerequisiteKey;
    private final ErrorKind errorKind;

    private static final EvaluationReason OFF_INSTANCE             = new EvaluationReason(Kind.OFF);
    private static final EvaluationReason FALLTHROUGH_INSTANCE     = new EvaluationReason(Kind.FALLTHROUGH);
    private static final EvaluationReason TARGET_MATCH_INSTANCE    = new EvaluationReason(Kind.TARGET_MATCH);
    private static final EvaluationReason ERROR_CLIENT_NOT_READY   = new EvaluationReason(ErrorKind.CLIENT_NOT_READY);
    private static final EvaluationReason ERROR_FLAG_NOT_FOUND     = new EvaluationReason(ErrorKind.FLAG_NOT_FOUND);
    private static final EvaluationReason ERROR_MALFORMED_FLAG     = new EvaluationReason(ErrorKind.MALFORMED_FLAG);
    private static final EvaluationReason ERROR_USER_NOT_SPECIFIED = new EvaluationReason(ErrorKind.USER_NOT_SPECIFIED);
    private static final EvaluationReason ERROR_WRONG_TYPE         = new EvaluationReason(ErrorKind.WRONG_TYPE);
    private static final EvaluationReason ERROR_EXCEPTION_THROWN   = new EvaluationReason(ErrorKind.EXCEPTION_THROWN);

    private EvaluationReason(Kind kind, Integer ruleIndex, String ruleId,
        String prerequisiteKey, ErrorKind errorKind)
    {
        this.kind            = kind;
        this.ruleIndex       = ruleIndex;
        this.ruleId          = ruleId;
        this.prerequisiteKey = prerequisiteKey;
        this.errorKind       = errorKind;
    }

    private EvaluationReason(Kind kind) {
        this.kind            = kind;
        this.ruleIndex       = null;
        this.ruleId          = null;
        this.prerequisiteKey = null;
        this.errorKind       = null;
    }

    private EvaluationReason(ErrorKind errorKind) {
        this.kind            = EvaluationReason.Kind.ERROR;
        this.ruleIndex       = null;
        this.ruleId          = null;
        this.prerequisiteKey = null;
        this.errorKind       = errorKind;
    }

    public static EvaluationReason off() {
        return OFF_INSTANCE;
    }

    public static EvaluationReason fallthrough() {
        return FALLTHROUGH_INSTANCE;
    }

    public static EvaluationReason targetMatch() {
        return TARGET_MATCH_INSTANCE;
    }

    public static EvaluationReason exception() {
        return ERROR_EXCEPTION_THROWN;
    }

    public static EvaluationReason prerequisiteFailed(String prerequisiteKey) {
        return new EvaluationReason(Kind.PREREQUISITE_FAILED, null, null, prerequisiteKey, null);
    }

    public static EvaluationReason ruleMatch(Integer ruleIndex, String ruleId) {
        return new EvaluationReason(Kind.RULE_MATCH, ruleIndex, ruleId, null, null);
    }

    public static EvaluationReason error(ErrorKind errorKind) {
        switch on errorKind {
            when CLIENT_NOT_READY {
                return ERROR_CLIENT_NOT_READY;
            }
            when FLAG_NOT_FOUND {
                return ERROR_FLAG_NOT_FOUND;
            }
            when MALFORMED_FLAG {
                return ERROR_MALFORMED_FLAG;
            }
            when USER_NOT_SPECIFIED {
                return ERROR_USER_NOT_SPECIFIED;
            }
            when WRONG_TYPE {
                return ERROR_WRONG_TYPE;
            }
        }

        return new EvaluationReason(errorKind);
    }

    public Kind getKind() {
        return this.kind;
    }

    public Integer getRuleIndex() {
        return this.ruleIndex;
    }

    public String kindToString(Kind kind) {
        switch on kind {
            when OFF {
                return 'OFF';
            }
            when FALLTHROUGH {
                return 'FALLTHROUGH';
            }
            when TARGET_MATCH {
                return 'TARGET_MATCH';
            }
            when RULE_MATCH {
                return 'RULE_MATCH';
            }
            when PREREQUISITE_FAILED {
                return 'PREREQUISITE_FAILED';
            }
            when ERROR {
                return 'ERROR';
            }
        }

        return 'unknown';
    }

    public String errorKindToString(ErrorKind errorKind) {
        switch on errorKind {
            when CLIENT_NOT_READY {
                return 'CLIENT_NOT_READY';
            }
            when FLAG_NOT_FOUND {
                return 'FLAG_NOT_FOUND';
            }
            when MALFORMED_FLAG {
                return 'MALFORMED_FLAG';
            }
            when USER_NOT_SPECIFIED {
                return 'USER_NOT_SPECIFIED';
            }
            when WRONG_TYPE {
                return 'WRONG_TYPE';
            }
            when EXCEPTION_THROWN {
                return 'EXCEPTION_THROWN';
            }
        }

        return 'unknown';
    }

    public Object toGeneric() {
        Map<String, Object> rep = new Map<String, Object>();

        rep.put('kind', this.kindToString(this.kind));

        switch on this.kind {
            when ERROR {
                rep.put('errorKind', this.errorKindToString(this.errorKind));
            }
            when PREREQUISITE_FAILED {
                rep.put('prerequisiteKey', this.prerequisiteKey);
            }
            when RULE_MATCH {
                rep.put('ruleIndex', this.ruleIndex);
                rep.put('ruleId', this.ruleId);
            }
            when else {
                // nothing
            }
        }

        return (Object)rep;
    }
}
