public class DataStore implements DataStoreInterface {
  private Map<String, Map<String, VersionedData__c>> versionedDataMap;

  public DataStore() {
  }

  private void populateVersioned() {
    // Preserve SOQL queries (each transaction only gets 100) by querying all data once
    // Data can them be retrieved via the map structure in the event that multiple data are needed at different times
    if (versionedDataMap == null) {
      versionedDataMap = new Map<String, Map<String, VersionedData__c>>{
        'flags' => new Map<String, VersionedData__c>(),
        'segments' => new Map<String, VersionedData__c>()
      };
      for (VersionedData__c vd : [
        SELECT Id, Version__c, Raw__c, Key__c, Kind__c
        FROM VersionedData__c
      ]) {
        versionedDataMap.get(vd.Kind__c).put(vd.Key__c, vd);
      }
    }
  }

  public VersionedData__c getVersioned(String key, String kind) {
    populateVersioned();
    return versionedDataMap.get(kind).get(key);
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
    populateVersioned();
    Map<String, DataModel.Flag> result = new Map<String, DataModel.Flag>();

    for (VersionedData__C flag : versionedDataMap.get('flags').values()) {
      try {
        result.put(flag.Key__c, new DataModel.Flag(flag.Raw__c));
      } catch (Exception err) {
        // required by compiler
      }
    }

    return result;
  }

  public void putAll(Map<String, Object> kinds) {
    // delete existing store values
    populateVersioned();
    List<VersionedData__c> existingFeatures = new List<VersionedData__c>();
    existingFeatures.addAll(versionedDataMap.get('flags').values());
    existingFeatures.addAll(versionedDataMap.get('segments').values());
    if (existingFeatures.size() > 0) {
      delete existingFeatures;
    }
    // iterate over kinds of features such as flags / segments
    List<VersionedData__c> featureList = new List<VersionedData__c>();
    for (String kind : kinds.keySet()) {
      Map<String, Object> features = (Map<String, Object>) kinds.get(kind);

      for (String key : features.keySet()) {
        Map<String, Object> feature = (Map<String, Object>) features.get(key);

        VersionedData versioned = new VersionedData(kind, feature);

        featureList.add(versioned.getSObject());
      }
    }
    if (featureList.size() > 0) {
      insert featureList;
    }

    // clear our versionedDataMap so that next time it is required it will be repopulated
    versionedDataMap = null;
  }
}
