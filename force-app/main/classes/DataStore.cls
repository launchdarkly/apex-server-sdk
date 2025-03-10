public class DataStore implements DataStoreInterface {
  private final Map<String, DataModel.Flag> flagsCache = new Map<String, DataModel.Flag>();
  private final Map<String, DataModel.Segment> segmentsCache = new Map<String, DataModel.Segment>();

  public DataStore() {
  }

  public VersionedData__C getVersioned(String key, String kind) {
    List<VersionedData__c> versioned = [
      SELECT Version__c, Raw__c, Key__c, Kind__c
      FROM VersionedData__c
      WHERE Key__c = :key AND Kind__c = :kind
      LIMIT 1
    ];

    if (versioned.isEmpty()) {
      return null;
    } else {
      return versioned.get(0);
    }
  }

  public DataModel.Flag getFlag(String key) {
    if (this.flagsCache.containsKey(key)) {
      return this.flagsCache.get(key);
    }

    VersionedData__c versioned = getVersioned(key, 'flags');

    if (versioned == null) {
      this.flagsCache.put(key, null);
      return null;
    } else {
      DataModel.Flag model = new DataModel.Flag(versioned.Raw__c);
      this.flagsCache.put(key, model);
      return model;
    }
  }

  public DataModel.Segment getSegment(String key) {
    if (this.segmentsCache.containsKey(key)) {
      return this.segmentsCache.get(key);
    }

    VersionedData__c versioned = getVersioned(key, 'segments');

    if (versioned == null) {
      return this.segmentsCache.put(key, null);
    } else {
      DataModel.Segment model = new DataModel.Segment(JSON.deserializeUntyped(versioned.Raw__c));
      this.segmentsCache.put(key, model);
      return model;
    }
  }

  public Map<String, DataModel.Flag> allFlags() {
    Map<String, DataModel.Flag> result = new Map<String, DataModel.Flag>();

    List<VersionedData__c> flags = [
      SELECT Version__c, Raw__c, Key__c, Kind__c
      FROM VersionedData__c
      WHERE Kind__c = 'flags'
    ];

    this.flagsCache.clear();

    for (VersionedData__C flag : flags) {
      try {
        DataModel.Flag model = new DataModel.Flag(flag.Raw__c);
        result.put(flag.Key__c, model);
        this.flagsCache.put(flag.Key__c, model);
      } catch (Exception err) {
        // required by compiler
      }
    }

    return result;
  }

  public void putAll(Map<String, Object> kinds) {
    // delete existing store values
    List<VersionedData__c> existingFeatures = [SELECT Key__c FROM VersionedData__C];
    delete existingFeatures;

    // Clear the cache. These will be re-hydrated as flags are requested.
    this.flagsCache.clear();
    this.segmentsCache.clear();

    // iterate over kinds of features such as flags / segments
    for (String kind : kinds.keySet()) {
      Map<String, Object> features = (Map<String, Object>) kinds.get(kind);

      for (String key : features.keySet()) {
        Map<String, Object> feature = (Map<String, Object>) features.get(key);

        VersionedData versioned = new VersionedData(kind, feature);

        this.insertVersionedData(versioned);
      }
    }
  }

  public void insertVersionedData(VersionedData value) {
    try {
      insert value.getSObject();
    } catch (Exception err) {
      // required by compiler
    }
  }
}
