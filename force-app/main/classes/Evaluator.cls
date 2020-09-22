public class Evaluator {
    public class EvalResult {
        private final LDValue          value;
        private final Integer          variationIndex;
        private final EvaluationReason reason;

        public EvalResult(LDValue value, Integer variationIndex, EvaluationReason reason) {
            this.value          = value;
            this.variationIndex = variationIndex;
            this.reason         = reason;
        }

        public EvalResult(EvaluationReason.ErrorKind errorKind) {
            this.value          = null;
            this.variationIndex = null;
            this.reason         = EvaluationReason.error(errorKind);
        }

        public LDValue getValue() {
            return this.value;
        }

        public Integer getVariationIndex() {
            return this.variationIndex;
        }

        public EvaluationReason getReason() {
            return this.reason;
        }
    }

    private final DataStoreInterface store;

    public Evaluator(DataStoreInterface store) {
        this.store = store;
    }

    public EvalResult evaluate(DataModel.Flag flag, LDUser user) {
        return this.evaluateInternal(flag, user);
    }

    private EvalResult evaluateInternal(DataModel.Flag flag, LDUser user) {
        if (!flag.isOn()) {
            return getOffValue(flag, EvaluationReason.off());
        }

        EvaluationReason prereqFailureReason = this.checkPrerequisites(flag, user);
        if (prereqFailureReason != null) {
            return this.getOffValue(flag, prereqFailureReason);
        }

        for (DataModel.Target target : flag.getTargets()) {
            if (target.getValues().contains(user.getKey())) {
                return this.getVariation(flag, target.getVariation(), EvaluationReason.targetMatch());
            }
        }

        List<DataModel.Rule> rules = flag.getRules();
        for (Integer i = 0; i < rules.size(); i++) {
            DataModel.Rule rule = rules.get(i);

            if (this.ruleMatchesUser(flag, rule, user)) {
                 EvaluationReason reason = EvaluationReason.ruleMatch(i, rule.getId());

                 return this.getValueForVariationOrRollout(flag, rule.getVariationOrRollout(), user, reason);
            }
        }

        return this.getValueForVariationOrRollout(flag, flag.getFallthrough(), user, EvaluationReason.fallthrough());
    }

    private EvaluationReason checkPrerequisites(DataModel.Flag flag, LDUser user) {
        for (DataModel.Prerequisite prereq : flag.getPrerequisites()) {
            Boolean prereqOk = true;

            DataModel.Flag prereqFeatureFlag = this.store.getFlag(prereq.getKey());

            if (prereqFeatureFlag == null) {
                prereqOk = false;
            } else {
                EvalResult prereqEvalResult = this.evaluateInternal(prereqFeatureFlag, user);

                if (!prereqFeatureFlag.isOn() || prereqEvalResult.getVariationIndex() != prereq.getVariation()) {
                    prereqOk = false;
                }
            }

            if (!prereqOk) {
                return EvaluationReason.prerequisiteFailed(prereq.getKey());
            }
        }

        return null;
    }

    private EvalResult getOffValue(DataModel.Flag flag, EvaluationReason reason) {
        Integer offVariation = flag.getOffVariation();

        if (offVariation == null) {
            return new EvalResult(null, -1, reason);
        } else {
            return getVariation(flag, offVariation, reason);
        }
    }

    private EvalResult getVariation(DataModel.Flag flag, Integer variation, EvaluationReason reason) {
        List<LDValue> variations = flag.getVariations();

        if (variation < 0 || variation >= variations.size()) {
            return new EvalResult(EvaluationReason.ErrorKind.MALFORMED_FLAG);
        } else {
            return new EvalResult(variations.get(variation), variation, reason);
        }
    }

    private EvalResult getValueForVariationOrRollout(DataModel.Flag flag, DataModel.VariationOrRollout vr, LDUser user, EvaluationReason reason) {
        Integer index = this.variationIndexForUser(vr, user, flag.getKey(), flag.getSalt());

        if (index == null) {
            return new EvalResult(EvaluationReason.ErrorKind.MALFORMED_FLAG);
        } else {
            return this.getVariation(flag, index, reason);
        }
    }

    private Boolean ruleMatchesUser(DataModel.Flag flag, DataModel.Rule rule, LDUser user) {
        for (DataModel.Clause clause: rule.getClauses()) {
            if (!this.clauseMatchesUser(clause, user)) {
                return false;
            }
        }

        return true;
    }

    private Boolean clauseMatchesUser(DataModel.Clause clause, LDUser user) {
        if (clause.getOperator().equals('SEGMENT_MATCH')) {
            for (LDValue j : clause.getValues()) {
                if (j.getType() == LDValueType.CString) {
                    DataModel.Segment segment = this.store.getSegment(j.stringValue());

                    if (segment != null) {
                        if (this.segmentMatchesUser(segment, user)) {
                            return this.maybeNegate(clause, true);
                        }
                    }
                }
            }

            return this.maybeNegate(clause, false);
        }

        return this.clauseMatchesUserNoSegments(clause, user);
    }

    private Boolean clauseMatchesUserNoSegments(DataModel.Clause clause, LDUser user) {
        LDValue userValue = null;

        if (userValue == null) {
            return false;
        }

        if (userValue.getType() == LDValueType.CARRAY) {
            for (Integer i = 0; i < userValue.size(); i++) {
                LDValue value = userValue.get(i);

                if (value.getType() == LDValueType.CARRAY || value.getType() == LDValueType.COBJECT) {
                    return false;
                }

                if (this.clauseMatchAny(clause, value)) {
                    return this.maybeNegate(clause, true);
                }
            }

            return this.maybeNegate(clause, false);
        } else if (userValue.getType() != LDValueType.COBJECT) {
            return maybeNegate(clause, this.clauseMatchAny(clause, userValue));
        }

        return false;
    }

    private Boolean clauseMatchAny(DataModel.Clause clause, LDValue userValue) {
        String op = clause.getOperator();

        if (op != null) {
            List<LDValue> values = clause.getValues();

            for (LDValue value : values) {
                if (EvaluatorOperators.apply(op, userValue, value)) {
                    return true;
                }
            }
        }

        return false;
    }

    private Boolean maybeNegate(DataModel.Clause clause, Boolean b) {
        return clause.isNegate() ? !b : b;
    }

    private Boolean segmentMatchesUser(DataModel.Segment segment, LDUser user) {
        String userKey = user.getKey();

        if (segment.getIncluded().contains(userKey)) {
            return true;
        }

        if (segment.getExcluded().contains(userKey)) {
            return false;
        }

        for (DataModel.SegmentRule rule : segment.getRules()) {
            if (this.segmentRuleMatchesUser(rule, user, segment.getKey(), segment.getSalt())) {
                return true;
            }
        }

        return false;
    }

    private Boolean segmentRuleMatchesUser(DataModel.SegmentRule segmentRule, LDUser user, String segmentKey, String salt) {
        for (DataModel.Clause c: segmentRule.getClauses()) {
            if (!this.clauseMatchesUserNoSegments(c, user)) {
                return false;
            }
        }

        if (segmentRule.getWeight() == null) {
            return true;
        }

        double bucket = this.bucketUser(user, segmentKey, segmentRule.getBucketBy(), salt);
        double weight = (double)segmentRule.getWeight() / 100000.0;

        return bucket < weight;
    }

    private Integer variationIndexForUser(DataModel.VariationOrRollout vr, LDUser user, String key, String salt) {
        Integer variation = vr.getVariation();

        if (variation != null) {
            return variation;
        } else {
            DataModel.Rollout rollout = vr.getRollout();

            if (rollout != null && !rollout.getVariations().isEmpty()) {
                Double bucket = this.bucketUser(user, key, rollout.getBucketBy(), salt);
                Double sum = 0;

                for (DataModel.WeightedVariation wv : rollout.getVariations()) {
                    sum += (Double)wv.getWeight() / (Double)100000.0;

                    if (bucket < sum) {
                        return wv.getVariation();
                    }
                }

                return rollout.getVariations().get(rollout.getVariations().size() - 1).getVariation();
            }
        }

        return null;
    }

    private Double bucketUser(LDUser user, String key, String attr, String salt) {
        LDValue userValue = user.getAttribute(attr == null ? 'key' : attr);
        String idHash = this.getBucketableStringValue(userValue);

        if (idHash != null) {
            if (user.getSecondary() != null){
                idHash = idHash + '.' + user.getSecondary();
            }

            Blob targetBlob = Blob.valueOf(key + '.' + salt + '.' + idHash);
            String hash = EncodingUtil.convertFromHex(EncodingUtil.convertToHex(
                Crypto.generateDigest('SHA1', targetBlob)).substring(0, 15)).toString();

            long longVal = long.valueOf(hash);

            return (Double)longVal / Double.valueOf('1152921504606846975');
        }

        return 0;
    }

    private String getBucketableStringValue(LDValue userValue) {
        switch on userValue.getType() {
            when CSTRING {
                return userValue.stringValue();
            }
            when CNUMBER {
                if (userValue.isInt()) {
                    return String.valueOf(userValue.intValue());
                } else {
                    return null;
                }
            }
            when else {
                return null;
            }
        }
    }
}
