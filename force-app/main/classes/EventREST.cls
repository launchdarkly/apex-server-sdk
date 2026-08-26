@RestResource(urlMapping='/event')
global with sharing class EventREST {
  // The bridge names its scope in a header rather than the body or the URL. A header is
  // invisible to a bridge or an org that predates scoping, so old and new versions of each
  // side interoperate in either upgrade order.
  public static final String SCOPE_HEADER = 'LD-Scope-Key';

  @HttpGet
  global static void doGet() {
    RestContext.response.addHeader('Content-Type', 'application/json');
    RestContext.response.responseBody = Blob.valueOf(
      JSON.serialize(EventREST.prepareEvents(ScopeHeader.read(RestContext.request, SCOPE_HEADER)))
    );
  }

  // Retained so existing callers keep compiling.
  public static Object prepareEvents() {
    return prepareEvents(null);
  }

  public static Object prepareEvents(String scope) {
    EventProcessor processor = new EventProcessor(new GetTimeImpl());

    // Scoped so a bridge only ever drains and deletes its own scope's events. An unscoped
    // drain delivers another scope's events to this bridge's environment under this bridge's
    // SDK key, and those events carry user attributes.
    //
    // The scope filter matches other casings as well, so narrow the rows before the drain
    // deletes them. Refer to eventsForScope for why this one keeps a fallback.
    List<EventData__c> events = CaseMatch.eventsForScope(
      [SELECT Kind__c, Raw__c, Scope__c FROM EventData__c WHERE Scope__c = :scope],
      scope
    );

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
