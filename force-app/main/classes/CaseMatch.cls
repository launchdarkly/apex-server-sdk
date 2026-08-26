// Narrows a project filter to one exact project.
//
// LaunchDarkly project keys are case sensitive. Salesforce compares text fields without regard
// to letter case, and it only allows a case-sensitive field when that field is also unique,
// which Project__c cannot be. A filter on the project therefore returns the records of every
// casing of the key.
//
// This SDK does not support project keys that differ only by case, and it does not try to make
// them work. It only stops one from destroying the data of a project that is supported. Reads
// are left alone: which record an unsupported key resolves to is undefined.
public class CaseMatch {
  // Two project keys name the same project. A null project means the records that carry no
  // project, which is a value here and not an absent one.
  public static Boolean sameProject(String wanted, String actual) {
    if (wanted == null) {
      return actual == null;
    }

    return wanted.equals(actual);
  }

  // The records of this exact project only. Use this before a delete. A delete gets no fallback
  // to the other casings: the first push of a new project finds no records of its own, so a
  // fallback would delete every record of the project whose key differs only by case.
  public static List<VersionedData__c> onlyProject(List<VersionedData__c> rows, String project) {
    List<VersionedData__c> exact = new List<VersionedData__c>();

    for (VersionedData__c row : rows) {
      if (sameProject(project, row.Project__c)) {
        exact.add(row);
      }
    }

    return exact;
  }

  // The events of this exact project, or every event when none belongs to it.
  //
  // This one keeps a fallback, unlike the delete above. The bridge drains events, and nothing
  // else does. A bridge whose project key differs in case from the Apex client that wrote the
  // events must still drain them, or they stay queued until they reach the queue cap. Two
  // projects whose keys differ only by case still drain separately, because each one has events
  // of its own that match exactly.
  public static List<EventData__c> scopeEventsToProject(List<EventData__c> rows, String project) {
    List<EventData__c> exact = new List<EventData__c>();

    for (EventData__c row : rows) {
      if (sameProject(project, row.Project__c)) {
        exact.add(row);
      }
    }

    if (exact.isEmpty()) {
      return rows;
    }

    return exact;
  }
}
