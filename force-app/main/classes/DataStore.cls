public class DataStore implements DataStoreInterface {
  // The LaunchDarkly project this store is scoped to. Null scopes it to records with no
  // project, which is what an org looks like before multi-project support and what a
  // bridge running without a project key continues to write.
  //
  // The project is bound here rather than passed per call so that every path through
  // Evaluator -- including prerequisite and segment lookups, which are made by key alone
  // -- stays within one project without Evaluator needing to know projects exist.
  private final String project;

  // Retained so existing callers keep compiling.
  public DataStore() {
    this(null);
  }

  public DataStore(String project) {
    this.project = project;
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
    VersionedData__c versioned = getVersioned(key, 'flags');

    if (versioned == null) {
      return null;
    } else {
      return new DataModel.Flag(versioned.Raw__c);
    }
  }

  public DataModel.Segment getSegment(String key) {
    VersionedData__c versioned = getVersioned(key, 'segments');

    if (versioned == null) {
      return null;
    } else {
      return new DataModel.Segment(JSON.deserializeUntyped(versioned.Raw__c));
    }
  }

  public Map<String, DataModel.Flag> allFlags() {
    Map<String, DataModel.Flag> result = new Map<String, DataModel.Flag>();

    List<VersionedData__c> flags = [
      SELECT Version__c, Raw__c, Key__c, Kind__c
      FROM VersionedData__c
      WHERE Kind__c = 'flags' AND Project__c = :project
    ];

    for (VersionedData__C flag : flags) {
      try {
        result.put(flag.Key__c, new DataModel.Flag(flag.Raw__c));
      } catch (Exception err) {
        // required by compiler
      }
    }

    return result;
  }

  public void putAll(Map<String, Object> kinds) {
    // Delete only this project's store values. An unscoped delete here would wipe every
    // other project's flag data on every push.
    delete [SELECT Key__c FROM VersionedData__c WHERE Project__c = :project];

    List<VersionedData__c> versionData = new List<VersionedData__c>();

    // iterate over kinds of features such as flags / segments
    for (String kind : kinds.keySet()) {
      Map<String, Object> features = (Map<String, Object>) kinds.get(kind);

      for (String key : features.keySet()) {
        Map<String, Object> feature = (Map<String, Object>) features.get(key);

        VersionedData versioned = new VersionedData(kind, feature, this.project);

        versionData.add(versioned.getSObject());
      }
    }

    try {
      insert versionData;
    } catch (Exception err) {
      // required by compiler
    }
  }
}
