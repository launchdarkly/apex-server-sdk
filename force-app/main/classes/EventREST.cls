@RestResource(urlMapping='/event')
global with sharing class EventREST {
  // The bridge names its scope in a header rather than the body or the URL. A header is
  // invisible to a bridge or an org that predates scoping, so old and new versions of each
  // side interoperate in either upgrade order.
  public static final String SCOPE_HEADER = 'LD-Scope-Key';

  // The rows one drain reads and deletes. A drain has to stay under three governor limits:
  // 10,000 DML rows, 50,000 query rows, and 6 MB of synchronous heap. An unbounded drain
  // throws before it reaches the delete once the table passes any of them, so nothing is
  // removed and the table can never shrink again.
  //
  // This number answers the two limits a row count can answer. It is five times under the DML
  // row limit and twenty-five times under the query row limit, so a drain cannot reach either.
  //
  // It also sits above maxEventsInQueue, which defaults to 1000. EventSink applies that cap to
  // the table on every insert, and it counts the same rows this drain queries. A bound below
  // the cap makes the drain rather than the cap decide how fast events leave the org: the
  // queue then sits at the cap and sinkGeneric drops every event that arrives. Above the cap
  // the default configuration drains completely on every poll.
  //
  // A row count cannot answer the heap limit. Raw__c is a long text field that holds up to
  // 131,072 characters, so the heap a drain needs follows total payload bytes and not rows.
  // How many rows fit in 6 MB depends on what an org puts in its flag values and its user
  // attributes, which this SDK cannot know. A row bound lowers the exposure in proportion to
  // itself. It does not remove it, and an org that raises maxEventsInQueue or carries large
  // flag values can still reach the heap limit at this number.
  public static final Integer MAX_EVENTS_PER_DRAIN = 2000;

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
    // The limit sits on the query because the query itself reaches the heap limit. A trim
    // after the query reads the rows before it drops them, which saves nothing.
    //
    // The order is oldest first, and Id breaks ties so that the order is total. A drain that
    // reads the same rows on every call never works through a backlog.
    List<EventData__c> window = [
      SELECT Kind__c, Raw__c, Scope__c
      FROM EventData__c
      WHERE Scope__c = :scope
      ORDER BY CreatedDate ASC, Id ASC
      LIMIT :MAX_EVENTS_PER_DRAIN
    ];

    // Salesforce compares text without regard to letter case, so the window can also hold the
    // rows of a scope key that differs from this one by case alone. No other scope reaches it,
    // because the query has already compared the keys. Those rows are left where they are,
    // and refer to onlyScope for why the drain gets no fallback to them.
    //
    // A drain reads a bounded window, so a key colliding on case can fill the window and hide
    // this scope's own rows below it. That scope then stops draining until the colliding rows
    // go. It takes more rows than maxEventsInQueue to reach, since the cap counts the casings
    // together, so batchEvents or a raised cap has to be in play as well. This SDK does not
    // support keys that differ only by case and does not try to make this case work.
    List<EventData__c> events = CaseMatch.onlyScope(window, scope);

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
