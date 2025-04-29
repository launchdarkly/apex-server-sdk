public class EventSink implements EventSinkInterface {
  Integer maxEvents;
  private Integer eventsAddedCount;
  private Integer existingEventsCount;

  public EventSink(Integer maxEvents) {
    System.assertNotEquals(maxEvents, null);

    this.maxEvents = maxEvents;
    this.eventsAddedCount = 0;
  }

  public void sinkIdentify(LDEvent.Identify event) {
    this.sinkGeneric('identify', JSON.serialize(event.toGeneric()));
  }

  public void sinkCustom(LDEvent.Custom event) {
    this.sinkGeneric('custom', JSON.serialize(event.toGeneric()));
  }

  public void sinkFeature(LDEvent.Feature event) {
    this.sinkGeneric('feature', JSON.serialize(event.toGeneric()));
  }

  public void sinkAlias(LDEvent.Alias event) {
    this.sinkGeneric('alias', JSON.serialize(event.toGeneric()));
  }

  public void sinkGeneric(String kind, String raw) {
    // Preserve SOQL queries (each transaction only gets 100) by getting count once and comparing to updated events count
    if (existingEventsCount == null) {
      existingEventsCount = [SELECT COUNT() FROM EventData__c];
    }
    // Only create event if threshold has not been met
    if ((existingEventsCount + eventsAddedCount) >= this.maxEvents) {
      return;
    }

    EventData__c record = new EventData__c();
    record.Kind__c = kind;
    record.Raw__c = raw;

    insert record;
    eventsAddedCount++;
  }

  public void flush() {
  }

  public void close() {
  }
}
