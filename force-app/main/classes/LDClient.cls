public class LDClient {
    private final LDConfig           config;
    private final DataStoreInterface store;
    private final Evaluator          evaluator;

    public class EvaluationDetail {
        private Integer          variationIndex;
        private EvaluationReason reason;

        EvaluationDetail() {
            this.variationIndex = null;
            this.reason         = null;
        }

        public Integer getVariationIndex() {
            return this.variationIndex;
        }

        public EvaluationReason getReason() {
            return this.reason;
        }
    }

    public LDClient(LDConfig config) {
        this.config    = config;
        this.store     = new DataStore();
        this.evaluator = new Evaluator(this.store);
    }

    public Boolean boolVariation(LDUser user, String key, Boolean fallback) {
        Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true);

        return result.getValue().booleanValue();
    }

    public Boolean boolVariation(LDUser user, String key, Boolean fallback, EvaluationDetail details) {
        Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true);

        details.variationIndex = result.getVariationIndex();
        details.reason         = result.getReason();

        return result.getValue().booleanValue();
    }

    public Integer intVariation(LDUser user, String key, Integer fallback) {
        Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true);

        return result.getValue().intValue();
    }

    public Integer intVariation(LDUser user, String key, Integer fallback, EvaluationDetail details) {
        Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true);

        details.variationIndex = result.getVariationIndex();
        details.reason         = result.getReason();

        return result.getValue().intValue();
    }

    public Double doubleVariation(LDUser user, String key, Double fallback) {
        Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true);

        return result.getValue().doubleValue();
    }

    public Double doubleVariation(LDUser user, String key, Double fallback, EvaluationDetail details) {
        Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true);

        details.variationIndex = result.getVariationIndex();
        details.reason         = result.getReason();

        return result.getValue().doubleValue();
    }

    public String stringVariation(LDUser user, String key, String fallback) {
        Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true);

        return result.getValue().stringValue();
    }

    public String stringVariation(LDUser user, String key, String fallback, EvaluationDetail details) {
        Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true);

        details.variationIndex = result.getVariationIndex();
        details.reason         = result.getReason();

        return result.getValue().stringValue();
    }

    public LDValue jsonVariation(LDUser user, String key, LDValue fallback) {
        Evaluator.EvalResult result = this.evaluateInternal(key, user, fallback, true);

        return result.getValue();
    }

    public LDValue jsonVariation(LDUser user, String key, LDValue fallback, EvaluationDetail details) {
        Evaluator.EvalResult result = this.evaluateInternal(key, user, fallback, true);

        details.variationIndex = result.getVariationIndex();
        details.reason         = result.getReason();

        return result.getValue();
    }

    private Evaluator.EvalResult evaluateInternal(String featureKey, LDUser user, LDValue defaultValue, Boolean checkType) {
        try {
            DataModel.Flag flag = this.store.getFlag(featureKey);

            if (flag == null) {
                return new Evaluator.EvalResult(defaultValue, -1, EvaluationReason.error(EvaluationReason.ErrorKind.FLAG_NOT_FOUND));
            }

            if (user == NULL) {
                return new Evaluator.EvalResult(defaultValue, -1, EvaluationReason.error(EvaluationReason.ErrorKind.USER_NOT_SPECIFIED));
            }

            Evaluator.EvalResult evalResult = evaluator.evaluate(flag, user);

            if (evalResult.getValue() == null) {
                return new Evaluator.EvalResult(defaultValue, -1, evalResult.getReason());
            } else {
                return evalResult;
            }
        } catch (Exception err) {
            return new Evaluator.EvalResult(defaultValue, -1, EvaluationReason.error(EvaluationReason.ErrorKind.EXCEPTION_THROWN));
        }
    }
}
