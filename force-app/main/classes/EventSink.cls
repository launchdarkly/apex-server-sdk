public class EventSink implements EventSinkInterface {
  Integer maxEvents;

  // The project events written by this sink belong to, and the scope of the queue cap.
  private final String project;

  // Retained so existing callers keep compiling.
  public EventSink(Integer maxEvents) {
    this(maxEvents, null);
  }

  public EventSink(Integer maxEvents, String project) {
    System.assertNotEquals(maxEvents, null);

    this.maxEvents = maxEvents;
    this.project = project;
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
    // Scoped to this project so maxEventsInQueue is a per-project cap. An unscoped count
    // lets another project's undrained events -- including rows orphaned by a
    // decommissioned bridge -- silently stop this project from recording events at all.
    Integer count = [SELECT COUNT() FROM EventData__c WHERE Project__c = :project];

    if (count >= this.maxEvents) {
      return;
    }

    EventData__c record = new EventData__c();
    record.Kind__c = kind;
    record.Raw__c = raw;
    record.Project__c = this.project;

    insert record;
  }

  public void flush() {
  }

  public void close() {
  }
}
