// Narrows a scope filter to one exact scope.
//
// LaunchDarkly keys are case sensitive. Salesforce compares text fields without regard to
// letter case, and it only allows a case-sensitive field when that field is also unique, which
// Scope__c cannot be. A filter on the scope therefore returns the records of every casing of
// the key.
//
// This SDK does not support scope keys that differ only by case, and it does not try to make
// them work. It only stops one from destroying the data of a scope that is supported. Reads
// are left alone: which record an unsupported key resolves to is undefined.
public class CaseMatch {
  // Two scope keys name the same scope. A null scope means the records that carry no scope,
  // which is a value here and not an absent one.
  public static Boolean sameScope(String wanted, String actual) {
    if (wanted == null) {
      return actual == null;
    }

    return wanted.equals(actual);
  }

  // The records of this exact scope only. Use this before a store push or an event drain.
  // Neither gets a fallback to the other casings, for a different reason each.
  //
  // A store push gets none because the first push of a new scope finds no records of its own,
  // so a fallback would delete every record of the scope whose key differs only by case.
  //
  // A drain gets none because it reads a bounded window. A fallback there cannot tell a scope
  // that has no events from one whose events sit below the window, so it would hand another
  // scope's events, and the user attributes they carry, to this bridge's environment under
  // this bridge's SDK key.
  public static List<VersionedData__c> onlyScope(List<VersionedData__c> rows, String scope) {
    List<VersionedData__c> exact = new List<VersionedData__c>();

    for (VersionedData__c row : rows) {
      if (sameScope(scope, row.Scope__c)) {
        exact.add(row);
      }
    }

    return exact;
  }

  // The events of this exact scope only. Refer to the overload above. Apex cannot write one
  // body for two SObject types without giving up the compiler's check on the field.
  public static List<EventData__c> onlyScope(List<EventData__c> rows, String scope) {
    List<EventData__c> exact = new List<EventData__c>();

    for (EventData__c row : rows) {
      if (sameScope(scope, row.Scope__c)) {
        exact.add(row);
      }
    }

    return exact;
  }
}
