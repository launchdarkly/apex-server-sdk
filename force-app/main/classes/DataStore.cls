public class DataStore implements DataStoreInterface {
  // The LaunchDarkly scope this store reads and writes. A scope is one environment of one
  // project, because a bridge authenticates with an SDK key and an SDK key names a single
  // environment. Null scopes the store to records that carry no scope, which is what an org
  // looks like before scoping and what a bridge running without a scope key keeps writing.
  //
  // The scope is bound here rather than passed per call so that every path through Evaluator
  // -- including prerequisite and segment lookups, which are made by key alone -- stays
  // inside one scope without Evaluator needing to know scopes exist.
  private final String scope;

  // Retained so existing callers keep compiling.
  public DataStore() {
    this(null);
  }

  public DataStore(String scope) {
    this.scope = scope;
  }

  public VersionedData__C getVersioned(String key, String kind) {
    List<VersionedData__c> versioned = [
      SELECT Version__c, Raw__c, Key__c, Kind__c
      FROM VersionedData__c
      WHERE Key__c = :key AND Kind__c = :kind AND Scope__c = :scope
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
      WHERE Kind__c = 'flags' AND Scope__c = :scope
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
    // Delete only this scope's store values. An unscoped delete here would wipe every other
    // scope's flag data on every push.
    //
    // The scope filter matches other casings of the key as well, so narrow the rows to this
    // exact scope before deleting them. Keys that differ only by case are not supported, but
    // an unsupported key must not destroy a supported scope's data: without this, a bridge
    // started with 'alpha' deletes everything belonging to 'Alpha' on every push.
    delete CaseMatch.onlyScope(
      [SELECT Key__c, Scope__c FROM VersionedData__c WHERE Scope__c = :scope],
      this.scope
    );

    List<VersionedData__c> versionData = new List<VersionedData__c>();

    // iterate over kinds of features such as flags / segments
    for (String kind : kinds.keySet()) {
      Map<String, Object> features = (Map<String, Object>) kinds.get(kind);

      for (String key : features.keySet()) {
        Map<String, Object> feature = (Map<String, Object>) features.get(key);

        VersionedData versioned = new VersionedData(kind, feature, this.scope);

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
