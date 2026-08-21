public class CachingDataStore implements DataStoreInterface {
  private final Map<String, DataModel.Flag> flagsCache = new Map<String, DataModel.Flag>();
  private final Map<String, DataModel.Segment> segmentsCache = new Map<String, DataModel.Segment>();

  private GetTimeInterface getTime;

  private final Integer ttl;
  private Long cachedAt;

  // Refer to the note in DataStore: bound here, not per call, so Evaluator's prerequisite
  // and segment lookups stay inside one project.
  private final String project;

  // Retained so existing callers keep compiling.
  public CachingDataStore(Integer ttl, GetTimeInterface getTime) {
    this(ttl, getTime, null);
  }

  public CachingDataStore(Integer ttl, GetTimeInterface getTime, String project) {
    System.assertNotEquals(ttl, null);

    this.getTime = getTime;

    this.ttl = ttl;
    this.cachedAt = null;
    this.project = project;
  }

  private void loadCache() {
    Long now = this.getTime.now();
    if (this.cachedAt != null && this.cachedAt + this.ttl > now) {
      return;
    }

    if (this.ttl == 0) {
      return;
    }

    this.flagsCache.clear();
    this.segmentsCache.clear();

    List<VersionedData__c> versionedData = [
      SELECT Version__c, Raw__c, Key__c, Kind__c
      FROM VersionedData__c
      WHERE Project__c = :project
    ];

    for (VersionedData__C datum : versionedData) {
      try {
        if (datum.Kind__c == 'flags') {
          DataModel.Flag model = new DataModel.Flag(datum.Raw__c);
          this.flagsCache.put(datum.Key__c, model);
        } else if (datum.Kind__c == 'segments') {
          DataModel.Segment model = new DataModel.Segment(JSON.deserializeUntyped(datum.Raw__c));
          this.segmentsCache.put(datum.Key__c, model);
        }
      } catch (Exception err) {
        // required by compiler
      }
    }

    this.cachedAt = now;
  }

  public VersionedData__C getVersioned(String key, String kind) {
    List<VersionedData__c> versioned = [
      SELECT Version__c, Raw__c, Key__c, Kind__c
      FROM VersionedData__c
      WHERE Key__c = :key AND Kind__c = :kind AND Project__c = :project
      LIMIT 1
    ];

    if (versioned.isEmpty()) {
      return null;
    } else {
      return versioned.get(0);
    }
  }

  public DataModel.Flag getFlag(String key) {
    this.loadCache();
    return this.flagsCache.get(key);
  }

  public DataModel.Segment getSegment(String key) {
    this.loadCache();
    return this.segmentsCache.get(key);
  }

  public Map<String, DataModel.Flag> allFlags() {
    this.loadCache();
    return this.flagsCache.clone();
  }

  public void putAll(Map<String, Object> kinds) {
    // Delete only this project's store values. An unscoped delete here would wipe every
    // other project's flag data on every push.
    List<VersionedData__c> existingFeatures = [
      SELECT Key__c
      FROM VersionedData__c
      WHERE Project__c = :project
    ];
    delete existingFeatures;

    // iterate over kinds of features such as flags / segments
    for (String kind : kinds.keySet()) {
      Map<String, Object> features = (Map<String, Object>) kinds.get(kind);

      for (String key : features.keySet()) {
        Map<String, Object> feature = (Map<String, Object>) features.get(key);
        VersionedData versioned = new VersionedData(kind, feature, this.project);

        this.insertVersionedData(versioned);
      }
    }
  }

  private void insertVersionedData(VersionedData value) {
    try {
      insert value.getSObject();
    } catch (Exception err) {
      // required by compiler
    }
  }
}
