@RestResource(urlMapping='/event')
global with sharing class EventREST {
  // The bridge names its scope in a header rather than the body or the URL. A header is
  // invisible to a bridge or an org that predates scoping, so old and new versions of each
  // side interoperate in either upgrade order.
  public static final String SCOPE_HEADER = 'LD-Scope-Key';

  // The query parameter a caller uses to ask one drain for fewer rows. A query parameter is
  // ignored by an org that predates it and omitted by a bridge that predates it, so the two
  // sides can be upgraded in either order.
  public static final String MAX_EVENTS_PARAM = 'maxEvents';

  // The most rows one drain reads and deletes, and the number used when the caller asks for
  // no limit of its own.
  //
  // A drain has to stay under three governor limits: 10,000 DML rows, 50,000 query rows, and
  // 6 MB of synchronous heap. An unbounded drain throws before it reaches the delete once the
  // table passes any of them, so nothing is removed and the table can never shrink again.
  //
  // The delete sets this number. A drain removes exactly the rows it read, and one
  // transaction can perform DML on 10,000 rows. The query row limit is five times looser, so
  // of the two limits a row count can answer, the delete is the binding one.
  //
  // A row count cannot answer the heap limit. Raw__c is a long text field that holds up to
  // 131,072 characters, so the heap a drain needs follows total payload bytes and not rows.
  // How many rows fit in 6 MB depends on what an org puts in its flag values and its user
  // attributes, which this SDK cannot know. A caller that reaches the heap limit at this
  // number asks for fewer rows, which needs no new release of this SDK.
  public static final Integer MAX_EVENTS_PER_DRAIN = 10000;

  @HttpGet
  global static void doGet() {
    RestContext.response.addHeader('Content-Type', 'application/json');

    Integer maxEvents = resolveMaxEvents(RestContext.request);

    // The caller named a limit this endpoint cannot use. Answer 400 and drain nothing.
    //
    // A caller lowers the limit to stay under a limit this SDK cannot measure for it, so
    // falling back to the default would ignore the request and throw in the way the caller
    // asked to avoid. A refusal says so instead.
    if (maxEvents == null) {
      RestContext.response.statusCode = 400;
      RestContext.response.responseBody = Blob.valueOf(
        JSON.serialize(
          new Map<String, Object>{ 'error' => MAX_EVENTS_PARAM + ' must be a positive integer' }
        )
      );

      return;
    }

    RestContext.response.responseBody = Blob.valueOf(
      JSON.serialize(
        EventREST.prepareEvents(ScopeHeader.read(RestContext.request, SCOPE_HEADER), maxEvents)
      )
    );
  }

  // The row limit for one drain, or null when the caller named one this endpoint cannot use.
  //
  // An absent or blank parameter reads as no request and gets MAX_EVENTS_PER_DRAIN, so a
  // bridge that predates the parameter behaves the same as one that sends the default.
  //
  // A request above MAX_EVENTS_PER_DRAIN is lowered to it rather than refused. A caller that
  // asks for more rows than the platform allows still drains.
  //
  // The parameter is read with a plain get, unlike the scan ScopeHeader needs. HTTP header
  // names are case-insensitive and an intermediary can change their casing. Query parameter
  // names are case-sensitive, and nothing between the caller and Apex rewrites them.
  public static Integer resolveMaxEvents(RestRequest request) {
    if (request == null || request.params == null) {
      return MAX_EVENTS_PER_DRAIN;
    }

    String raw = request.params.get(MAX_EVENTS_PARAM);

    if (String.isBlank(raw)) {
      return MAX_EVENTS_PER_DRAIN;
    }

    Integer requested;

    // Integer.valueOf throws on text that is not a number, and on a number too large to hold
    // in an Integer. Both are the same bad request here.
    try {
      requested = Integer.valueOf(raw.trim());
    } catch (Exception parseFailed) {
      return null;
    }

    if (requested <= 0) {
      return null;
    }

    if (requested > MAX_EVENTS_PER_DRAIN) {
      return MAX_EVENTS_PER_DRAIN;
    }

    return requested;
  }

  // Retained so existing callers keep compiling.
  public static Object prepareEvents() {
    return prepareEvents(null, MAX_EVENTS_PER_DRAIN);
  }

  // Retained so existing callers keep compiling.
  public static Object prepareEvents(String scope) {
    return prepareEvents(scope, MAX_EVENTS_PER_DRAIN);
  }

  public static Object prepareEvents(String scope, Integer maxEvents) {
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
      LIMIT :maxEvents
    ];

    // Salesforce compares text without regard to letter case, so the window can also hold the
    // rows of a scope key that differs from this one by case alone. No other scope reaches it,
    // because the query has already compared the keys. Those rows are left where they are,
    // and refer to onlyScope for why the drain gets no fallback to them.
    //
    // A drain reads a bounded window, so a key colliding on case can fill the window and hide
    // this scope's own rows below it. That scope then stops draining until the colliding rows
    // go. This SDK does not support keys that differ only by case and does not try to make
    // this case work.
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
