public class EventProcessor {
  private Map<String, FlagContext> flagContexts;
  private Long summaryStartTime;
  private GetTimeInterface getTime;
  private List<Object> events;

  private class CounterContext {
    public Object value;
    public Integer count;
    public Integer version;
    public Integer variation;
    public Boolean unknown;

    CounterContext(Object value, Integer version, Integer variation, Boolean unknown) {
      this.value = value;
      this.count = 0;
      this.version = version;
      this.variation = variation;
      this.unknown = unknown;
    }

    public void increment() {
      this.count++;
    }
  }

  private class FlagContext {
    public Object defaultValue;
    public Map<String, CounterContext> counters;

    FlagContext(Object defaultValue) {
      this.defaultValue = defaultValue;
      this.counters = new Map<String, CounterContext>();
    }

    public CounterContext lookup(String key) {
      return this.counters.get(key);
    }

    public void addCounter(String key, CounterContext context) {
      this.counters.put(key, context);
    }
  }

  public EventProcessor(GetTimeInterface getTime) {
    this.flagContexts = new Map<String, FlagContext>();
    this.summaryStartTime = null;
    this.getTime = getTime;
    this.events = new List<Object>();
  }

  private String makeSummaryKey(LDEvent.Feature event) {
    String key = '';

    Integer variation = event.getVariation();
    if (variation != null) {
      key += String.valueOf(variation);
    }

    key += '.';

    Integer version = event.getVersion();
    if (version != null) {
      key += String.valueOf(version);
    }

    return key;
  }

  public void summarizeFeatureEvent(LDEvent.Feature event) {
    if (this.summaryStartTime == null) {
      this.summaryStartTime = this.getTime.now();
    }

    FlagContext flagContext = this.flagContexts.get(event.getKey());

    if (flagContext == null) {
      flagContext = new FlagContext(event.getDefaultValue());

      this.flagContexts.put(event.getKey(), flagContext);
    }

    String summaryKey = this.makeSummaryKey(event);

    CounterContext counterContext = flagContext.lookup(summaryKey);

    if (counterContext == null) {
      counterContext = new CounterContext(
        event.getValue(),
        event.getVersion(),
        event.getVariation(),
        event.getUnknown()
      );

      flagContext.addCounter(summaryKey, counterContext);
    }

    counterContext.increment();
  }

  public void processFeatureEvent(LDEvent.Feature event) {
    this.summarizeFeatureEvent(event);

    if (event.getTrackEvents()) {
      Map<String, Object> eventGeneric = (Map<String, Object>) event.toGeneric();

      eventGeneric.remove('trackEvents');
      eventGeneric.remove('unknown');
      eventGeneric.remove('debug');

      this.events.add((Object) eventGeneric);
    }
  }

  public void addProcessedEvent(Object event) {
    this.events.add(event);
  }

  public Object buildSummaryEvent() {
    if (this.flagContexts.isEmpty()) {
      return null;
    }

    Map<String, Object> event = new Map<String, Object>();

    event.put('kind', 'summary');

    Map<String, Object> outFlagContexts = new Map<String, Object>();

    event.put('features', outFlagContexts);

    event.put('startDate', this.summaryStartTime);
    event.put('endDate', this.getTime.now());

    for (String flagKey : this.flagContexts.keySet()) {
      FlagContext flagContext = this.flagContexts.get(flagKey);

      Map<String, Object> outFlagContext = new Map<String, Object>();

      outFlagContext.put('default', flagContext.defaultValue);

      List<Object> outCounters = new List<Object>();

      outFlagContext.put('counters', outCounters);

      for (String summaryKey : flagContext.counters.keySet()) {
        CounterContext counterContext = flagContext.counters.get(summaryKey);

        Map<String, Object> outCounter = new Map<String, Object>();

        outCounter.put('count', counterContext.count);

        if (counterContext.version != null) {
          outCounter.put('version', counterContext.version);
        }

        if (counterContext.variation != null) {
          outCounter.put('variation', counterContext.variation);
        }

        if (counterContext.value != null) {
          outCounter.put('value', counterContext.value);
        }

        if (counterContext.unknown == true) {
          outCounter.put('unknown', true);
        }

        outCounters.add(outCounter);
      }

      outFlagContexts.put(flagKey, outFlagContext);
    }

    return (Object) event;
  }

  public Object buildEventBundle() {
    Object summaryEvent = this.buildSummaryEvent();

    if (summaryEvent != null) {
      this.events.add(summaryEvent);
    }

    return (Object) this.events;
  }
}
