public class LDClient {
  private final LDConfig config;
  private final DataStoreInterface store;
  private final Evaluator evaluator;
  private final EventSinkInterface eventSink;
  public GetTimeInterface getTime;

  public class EvaluationDetail {
    private Integer variationIndex;
    private EvaluationReason reason;

    public EvaluationDetail() {
      this.variationIndex = null;
      this.reason = null;
    }

    public Integer getVariationIndex() {
      return this.variationIndex;
    }

    public EvaluationReason getReason() {
      return this.reason;
    }
  }

  public LDClient(LDConfig config) {
    if (config == null) {
      this.config = new LDConfig.Builder().build();
    } else {
      this.config = config;
    }

    this.getTime = new GetTimeImpl();
    if (config.getCacheTtl() != null) {
      this.store = new CachingDataStore(config.getCacheTtl(), this.getTime);
    } else {
      this.store = new DataStore();
    }

    if (config.getBatchEvents()) {
      this.eventSink = new BatchingEventSink(this.config.getMaxEventsInQueue());
    } else {
      this.eventSink = new EventSink(this.config.getMaxEventsInQueue());
    }

    this.evaluator = new Evaluator(this.store, this.getTime);
  }

  public LDClient() {
    this(new LDConfig.Builder().build());
  }

  public void close() {
    this.eventSink.close();
  }

  public Boolean boolVariation(LDUser user, String key, Boolean fallback) {
    Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true, false);

    return result.getValue().booleanValue();
  }

  public Boolean boolVariation(LDUser user, String key, Boolean fallback, EvaluationDetail details) {
    Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true, true);

    details.variationIndex = result.getVariationIndex();
    details.reason = result.getReason();

    return result.getValue().booleanValue();
  }

  public Integer intVariation(LDUser user, String key, Integer fallback) {
    Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true, false);

    return result.getValue().intValue();
  }

  public Integer intVariation(LDUser user, String key, Integer fallback, EvaluationDetail details) {
    Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true, true);

    details.variationIndex = result.getVariationIndex();
    details.reason = result.getReason();

    return result.getValue().intValue();
  }

  public Double doubleVariation(LDUser user, String key, Double fallback) {
    Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true, false);

    return result.getValue().doubleValue();
  }

  public Double doubleVariation(LDUser user, String key, Double fallback, EvaluationDetail details) {
    Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true, true);

    details.variationIndex = result.getVariationIndex();
    details.reason = result.getReason();

    return result.getValue().doubleValue();
  }

  public String stringVariation(LDUser user, String key, String fallback) {
    Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true, false);

    return result.getValue().stringValue();
  }

  public String stringVariation(LDUser user, String key, String fallback, EvaluationDetail details) {
    Evaluator.EvalResult result = this.evaluateInternal(key, user, LDValue.of(fallback), true, true);

    details.variationIndex = result.getVariationIndex();
    details.reason = result.getReason();

    return result.getValue().stringValue();
  }

  public LDValue jsonVariation(LDUser user, String key, LDValue fallback) {
    Evaluator.EvalResult result = this.evaluateInternal(key, user, fallback, true, false);

    return result.getValue();
  }

  public LDValue jsonVariation(LDUser user, String key, LDValue fallback, EvaluationDetail details) {
    Evaluator.EvalResult result = this.evaluateInternal(key, user, fallback, true, true);

    details.variationIndex = result.getVariationIndex();
    details.reason = result.getReason();

    return result.getValue();
  }

  public Map<String, LDValue> allFlags(LDUser user) {
    if (user == null || user.getKey() == null) {
      return null;
    }

    Map<String, LDValue> result = new Map<String, LDValue>();

    Map<String, DataModel.Flag> flags = this.store.allFlags();

    for (String flagKey : flags.keySet()) {
      DataModel.Flag flag = flags.get(flagKey);

      Evaluator.EvalResult evalResult = evaluator.evaluate(flag, user, false);

      if (evalResult.getValue() != null) {
        result.put(flagKey, evalResult.getValue());
      }
    }

    return result;
  }

  public void identify(LDUser user) {
    if (user == null || user.getKey() == null) {
      return;
    }

    this.eventSink.sinkIdentify(new LDEvent.Identify(user, this.getTime.now(), config.getAllAttributesPrivate()));
  }

  public void track(LDUser user, String key, Double optionalMetric, LDValue optionalValue) {
    if (user == null || user.getKey() == null || key == null) {
      return;
    }

    this.eventSink.sinkCustom(
      new LDEvent.Custom(user, key, optionalMetric, optionalValue, this.getTime.now(), config.getAllAttributesPrivate())
    );
  }

  public void alias(LDUser currentUser, LDUser previousUser) {
    if (currentUser == null || currentUser.getKey() == null || previousUser == null || previousUser.getKey() == null) {
      return;
    }

    this.eventSink.sinkAlias(new LDEvent.Alias(currentUser, previousUser, this.getTime.now()));
  }

  private Evaluator.EvalResult evaluateInternal(
    String featureKey,
    LDUser user,
    LDValue defaultValue,
    Boolean checkType,
    Boolean includeReasonInEvents
  ) {
    DataModel.Flag flag = this.store.getFlag(featureKey);

    if (flag == null) {
      EvaluationReason reason;

      if (includeReasonInEvents) {
        reason = EvaluationReason.error(EvaluationReason.ErrorKind.FLAG_NOT_FOUND);
      }

      LDEvent.Feature event = new LDEvent.Feature(
        featureKey, // key
        user, // user
        null, // version
        null, // variation
        defaultValue, // value
        defaultValue, // defaultValue
        reason, // reason
        null, // prereqOf
        false, // trackEvents
        null, // debugEventsUntilDate
        false, // debug
        true, // unknown
        this.getTime.now(), // now
        config.getAllAttributesPrivate() // allAttributesPrivate
      );

      this.eventSink.sinkFeature(event);

      return new Evaluator.EvalResult(defaultValue, null, reason);
    }

    if (user == null || user.getKey() == null) {
      EvaluationReason reason;

      if (includeReasonInEvents) {
        reason = EvaluationReason.error(EvaluationReason.ErrorKind.USER_NOT_SPECIFIED);
      }

      LDEvent.Feature event = new LDEvent.Feature(
        featureKey, // key
        user, // user
        null, // version
        null, // variation
        defaultValue, // value
        defaultValue, // defaultValue
        reason, // reason
        null, // prereqOf
        false, // trackEvents
        null, // debugEventsUntilDate
        false, // debug
        false, // unknown
        this.getTime.now(), // now
        config.getAllAttributesPrivate() // allAttributesPrivate
      );

      this.eventSink.sinkFeature(event);

      return new Evaluator.EvalResult(defaultValue, null, reason);
    }

    Evaluator.EvalResult evalResult = evaluator.evaluate(flag, user, includeReasonInEvents);

    if (evalResult.getValue() == null) {
      evalResult = new Evaluator.EvalResult(defaultValue, null, evalResult.getReason());
    }

    Boolean requireExperimentData = this.evaluator.isExperiment(flag, evalResult.getReason());

    EvaluationReason reason;

    if (includeReasonInEvents || this.evaluator.shouldForceReason(flag, evalResult.getReason())) {
      reason = evalResult.getReason();
    }

    LDEvent.Feature event = new LDEvent.Feature(
      featureKey, // key
      user, // user
      flag.getVersion(), // version
      evalResult.getVariationIndex(), // variation
      evalResult.getValue(), // value
      defaultValue, // defaultValue
      reason, // reason
      null, // prereqOf
      requireExperimentData ||
      flag.getTrackEvents(), // trackEvents
      flag.getDebugEventsUntilDate(), // debugEventsUntilDate
      false, // debug
      false, // unknown
      this.getTime.now(), // now
      config.getAllAttributesPrivate() // allAttributesPrivate
    );

    this.eventSink.sinkFeature(event);

    for (LDEvent.Feature prereqEvent : evalResult.getPrerequisiteEvents()) {
      this.eventSink.sinkFeature(prereqEvent);
    }

    return evalResult;
  }
}
