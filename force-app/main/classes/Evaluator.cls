public class Evaluator {
    public class EvalResult {
        private final LDValue             value;
        private final Integer             variationIndex;
        private final EvaluationReason    reason;
        private       List<Event.Feature> prerequisiteEvents;

        public EvalResult(LDValue value, Integer variationIndex, EvaluationReason reason) {
            this.value              = value;
            this.variationIndex     = variationIndex;
            this.reason             = reason;
            this.prerequisiteEvents = new List<Event.Feature>();
        }

        public EvalResult(EvaluationReason.ErrorKind errorKind) {
            this.value              = null;
            this.variationIndex     = null;
            this.reason             = EvaluationReason.error(errorKind);
            this.prerequisiteEvents = new List<Event.Feature>();
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

        public List<Event.Feature> getPrerequisiteEvents() {
            return this.prerequisiteEvents;
        }

        public void setPrerequisiteEvents(List<Event.Feature> prerequisiteEvents) {
            this.prerequisiteEvents = prerequisiteEvents;
        }
    }

    private final DataStoreInterface store;
    private final GetTimeInterface   getTime;

    public Evaluator(DataStoreInterface store, GetTimeInterface getTime) {
        this.store   = store;
        this.getTime = getTime;
    }

    public EvalResult evaluate(DataModel.Flag flag, LDUser user, Boolean includeReasonInEvents) {
        List<Event.Feature> events = new List<Event.Feature>();

        EvalResult result = this.evaluateInternal(flag, user, events, includeReasonInEvents);

        result.setPrerequisiteEvents(events);

        return result;
    }

    private EvalResult evaluateInternal(
        DataModel.Flag      flag,
        LDUser              user,
        List<Event.Feature> eventsOut,
        Boolean             includeReasonInEvents
    ) {
        if (!flag.isOn()) {
            return getOffValue(flag, EvaluationReason.off());
        }

        EvaluationReason prereqFailureReason = this.checkPrerequisites(flag, user, eventsOut, includeReasonInEvents);
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
                VariationIndexForUserResult indexResult = this.variationIndexForUser(
                    rule.getVariationOrRollout(),
                    user,
                    flag.getKey(),
                    flag.getSalt()
                );

                if (indexResult == null) {
                    return new EvalResult(EvaluationReason.ErrorKind.MALFORMED_FLAG);
                }

                return this.getVariation(
                    flag,
                    indexResult.variationIndex,
                    EvaluationReason.ruleMatch(i, rule.getId(), indexResult.inExperiment)
                );
            }
        }

        return this.getFallthroughResult(flag, user);
    }

    private EvalResult getFallthroughResult(
        DataModel.Flag flag,
        LDUser         user
    ) {
        VariationIndexForUserResult indexResult = this.variationIndexForUser(
            flag.getFallthrough(),
            user,
            flag.getKey(),
            flag.getSalt()
        );

        if (indexResult == null) {
            return new EvalResult(EvaluationReason.ErrorKind.MALFORMED_FLAG);
        }

        return this.getVariation(
            flag,
            indexResult.variationIndex,
            EvaluationReason.fallthrough(indexResult.inExperiment)
        );
    }

    public Boolean shouldForceReason(DataModel.Flag flag, EvaluationReason reason) {
        if (reason.getKind() == EvaluationReason.Kind.FALLTHROUGH) {
            return flag.getTrackEventsFallthrough();
        } else if (reason.getKind() == EvaluationReason.Kind.RULE_MATCH) {
            return flag.getRules().get(reason.getRuleIndex()).shouldTrackEvents();
        }

        return false;
    }

    public Boolean isExperiment(DataModel.Flag flag, EvaluationReason reason) {
        switch on reason.getKind() {
            when FALLTHROUGH {
                return reason.isInExperiment() || flag.getTrackEventsFallthrough();
            }
            when RULE_MATCH {
                if (reason.isInExperiment()) {
                    return true;
                }

                Integer index = reason.getRuleIndex();

                if (index >= 0 && index < flag.getRules().size()) {
                    return flag.getRules().get(index).shouldTrackEvents();
                }

                return false;
            }
            when else {
                return false;
            }
        }
    }

    private EvaluationReason checkPrerequisites(
        DataModel.Flag      flag,
        LDUser              user,
        List<Event.Feature> eventsOut,
        Boolean             includeReasonInEvents
    ) {
        for (DataModel.Prerequisite prereq : flag.getPrerequisites()) {
            Boolean prereqOk = true;

            DataModel.Flag prereqFeatureFlag = this.store.getFlag(prereq.getKey());

            if (prereqFeatureFlag == null) {
                prereqOk = false;
            } else {
                EvalResult prereqEvalResult = this.evaluateInternal(prereqFeatureFlag, user, eventsOut, includeReasonInEvents);

                if (!prereqFeatureFlag.isOn() || prereqEvalResult.getVariationIndex() != prereq.getVariation()) {
                    prereqOk = false;
                }

                Boolean requireExperimentData =
                    this.isExperiment(prereqFeatureFlag, prereqEvalResult.getReason());

                EvaluationReason reason;

                if (includeReasonInEvents || this.shouldForceReason(prereqFeatureFlag, prereqEvalResult.getReason())) {
                    reason = prereqEvalResult.getReason();
                }

                Event.Feature event = new Event.Feature(
                    prereq.getKey(), // key
                    user, // user
                    prereqFeatureFlag.getVersion(), // version
                    prereqEvalResult.getVariationIndex(), // variation
                    prereqEvalResult.getValue(), // value
                    null, // defaultValue
                    reason, // reason
                    flag.getKey(), // prereqOf
                    requireExperimentData || prereqFeatureFlag.getTrackEvents(), // trackEvents
                    prereqFeatureFlag.getDebugEventsUntilDate(), // debugEventsUntilDate
                    false, // debug
                    false, // unknown
                    this.getTime.now(), // now
                    false // allAttributesPrivate
                );
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
            return new EvalResult(null, null, reason);
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

    private Boolean ruleMatchesUser(DataModel.Flag flag, DataModel.Rule rule, LDUser user) {
        for (DataModel.Clause clause: rule.getClauses()) {
            if (!this.clauseMatchesUser(clause, user)) {
                return false;
            }
        }

        return true;
    }

    private Boolean clauseMatchesUser(DataModel.Clause clause, LDUser user) {
        if (clause.getOperator().equals('segmentMatch')) {
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
        LDValue userValue = user.getAttribute(clause.getAttribute());

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

        double bucket = this.bucketUser(user, segmentKey, segmentRule.getBucketBy(), salt, null);
        double weight = (double)segmentRule.getWeight() / 100000.0;

        return bucket < weight;
    }

    public class VariationIndexForUserResult {
        public final Integer variationIndex;
        public final Boolean inExperiment;

        public VariationIndexForUserResult(Integer variationIndex, Boolean inExperiment) {
            this.variationIndex = variationIndex;
            this.inExperiment   = inExperiment;
        }
    }

    public VariationIndexForUserResult variationIndexForUser(DataModel.VariationOrRollout vr, LDUser user, String key, String salt) {
        Integer variation = vr.getVariation();

        if (variation != null) {
            return new VariationIndexForUserResult(variation, false);
        } else {
            DataModel.Rollout rollout = vr.getRollout();

            if (rollout != null && !rollout.getVariations().isEmpty()) {
                Boolean inExperiment = rollout.getKind() == DataModel.RolloutKind.EXPERIMENT;

                Double bucket = this.bucketUser(user, key, rollout.getBucketBy(), salt, rollout.getSeed());
                Double sum = 0;

                for (DataModel.WeightedVariation wv : rollout.getVariations()) {
                    sum += (Double)wv.getWeight() / (Double)100000.0;

                    if (bucket < sum) {
                        return new VariationIndexForUserResult(wv.getVariation(), !wv.isUntracked() && inExperiment);
                    }
                }

                DataModel.WeightedVariation wv = rollout.getVariations().get(rollout.getVariations().size() - 1);

                return new VariationIndexForUserResult(wv.getVariation(), !wv.isUntracked() && inExperiment);
            }
        }

        return null;
    }

    public Decimal hexToDecimal(String input) {
        String alphabet = '0123456789abcdef';

        Decimal acc = 0;

        for(Integer index = 0; index < input.length(); index++) {
            acc = (acc * 16) + alphabet.indexOf(input.subString(index, index + 1));

        }
        return acc;
    }

    public Double bucketUser(LDUser user, String key, String attr, String salt, Integer seed) {
        LDValue userValue = user.getAttribute(attr == null ? 'key' : attr);

        if (userValue == null) {
            return 0;
        }

        String idHash = this.getBucketableStringValue(userValue);

        if (idHash != null) {
            String secondarySuffix = '';

            if (user.getSecondary() != null) {
                secondarySuffix = '.' + user.getSecondary();
            }

            Blob targetBlob;

            if (seed != null) {
                targetBlob = Blob.valueOf(String.valueOf(seed) + '.' + idHash + secondarySuffix);
            } else {
                targetBlob = Blob.valueOf(key + '.' + salt + '.' + idHash + secondarySuffix);
            }

            String hash = EncodingUtil.convertToHex(Crypto.generateDigest('SHA1', targetBlob))
                .substring(0, 15);
                
            Double full = (Double)this.hexToDecimal(hash) / Double.valueOf('1152921504606846975');

            return (Double)((Decimal)(full)).setScale(8);
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
