public class BatchingEventSink implements EventSinkInterface {
  List<EventData__c> events;
  Integer maxEvents;

  public BatchingEventSink(Integer maxEvents) {
    System.assertNotEquals(maxEvents, null);

    this.maxEvents = maxEvents;
    this.events = new List<EventData__c>();
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
    if (events.size() >= this.maxEvents) {
      return;
    }

    EventData__c record = new EventData__c();
    record.Kind__c = kind;
    record.Raw__c = raw;

    this.events.add(record);
  }

  public void close() {
    this.flush();

    // This disables the sink from receiving more events after it's closed
    this.maxEvents = 0;
  }

  public void flush() {
    if (events.size() > 0) {
      insert events;
    }
  }
}
