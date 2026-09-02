@RestResource(urlMapping='/event')
global with sharing class EventREST {
  // The bridge names its scope in a header rather than the body or the URL. A header is
  // invisible to a bridge or an org that predates scoping, so old and new versions of each
  // side interoperate in either upgrade order.
  public static final String SCOPE_HEADER = 'LD-Scope-Key';

  // The rows one drain reads and deletes. A drain has to stay under three governor limits:
  // 6 MB of synchronous heap, 10,000 DML rows, and 50,000 query rows. An unbounded drain
  // throws before it reaches the delete once the table passes any of them, so nothing is
  // removed and the table can never shrink again.
  //
  // A row count does not bound heap by itself. Raw__c is a long text field that holds up to
  // 131,072 characters, so the cost of a drain follows total payload bytes rather than rows.
  // This number rests on an average Raw__c of a few kilobytes. A typical event serializes to
  // 200-700 bytes, and the largest realistic one -- a JSON flag value, which is serialized
  // into both value and default -- costs about 6 KB. Even at 6 KB a drain reads 1.2 MB, which
  // leaves the rest of the heap for the parsed events and the bundle built from them. An org
  // whose events run far larger than that needs a smaller number here.
  //
  // The bridge polls every 30 seconds and a backlog simply takes more polls to clear, so a
  // small number costs delivery latency on a backlog and nothing in steady state.
  public static final Integer MAX_EVENTS_PER_DRAIN = 200;

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
    //
    // The limit sits on the query because the query itself reaches the heap limit. A trim
    // after the query reads the rows before it drops them, which saves nothing.
    //
    // The order is oldest first, and Id breaks ties so that the order is total. A drain that
    // reads the same rows on every call never works through a backlog.
    //
    // eventsForScope narrows the window after it is read, so a scoped drain can return fewer
    // rows than the limit. Only a key that differs from this scope's key by letter case can
    // hold a slot in the window, since Salesforce has already compared the keys without
    // regard to case. Such a key is unsupported, and the fallback drains the window whenever
    // it holds none of this scope's rows, so every drain deletes at least one row it read.
    // That is what lets a table already past a governor limit shrink on repeated drains.
    List<EventData__c> events = CaseMatch.eventsForScope(
      [
        SELECT Kind__c, Raw__c, Scope__c
        FROM EventData__c
        WHERE Scope__c = :scope
        ORDER BY CreatedDate ASC, Id ASC
        LIMIT :MAX_EVENTS_PER_DRAIN
      ],
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
