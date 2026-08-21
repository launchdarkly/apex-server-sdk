@RestResource(urlMapping='/event')
global with sharing class EventREST {
  // The bridge names its project in a header rather than the body or the URL. A header is
  // invisible to a bridge or an org that predates multi-project support, so old and new
  // versions of each side interoperate in either upgrade order.
  public static final String PROJECT_HEADER = 'LD-Project-Key';

  @HttpGet
  global static void doGet() {
    RestContext.response.addHeader('Content-Type', 'application/json');
    RestContext.response.responseBody = Blob.valueOf(
      JSON.serialize(EventREST.prepareEvents(ProjectHeader.read(RestContext.request, PROJECT_HEADER)))
    );
  }

  // Retained so existing callers keep compiling.
  public static Object prepareEvents() {
    return prepareEvents(null);
  }

  public static Object prepareEvents(String project) {
    EventProcessor processor = new EventProcessor(new GetTimeImpl());

    // Scoped so a bridge only ever drains and deletes its own project's events. An
    // unscoped drain delivers another project's events to this bridge's environment under
    // this bridge's SDK key, and those events carry user attributes.
    List<EventData__c> events = [
      SELECT Kind__c, Raw__c
      FROM EventData__c
      WHERE Project__c = :project
    ];

    for (EventData__c event : events) {
      switch on event.Kind__c {
        when 'feature' {
          Object parsed = (Object) JSON.deserializeUntyped(event.Raw__c);
          LDEvent.Feature featureEvent = new LDEvent.Feature(parsed);
          processor.processFeatureEvent(featureEvent);
        }
        when else {
          processor.addProcessedEvent(JSON.deserializeUntyped(event.Raw__c));
        }
      }
    }

    delete events;

    return processor.buildEventBundle();
  }
}
