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

  // The records of this exact scope only. Use this before a delete. A delete gets no fallback
  // to the other casings: the first push of a new scope finds no records of its own, so a
  // fallback would delete every record of the scope whose key differs only by case.
  public static List<VersionedData__c> onlyScope(List<VersionedData__c> rows, String scope) {
    List<VersionedData__c> exact = new List<VersionedData__c>();

    for (VersionedData__c row : rows) {
      if (sameScope(scope, row.Scope__c)) {
        exact.add(row);
      }
    }

    return exact;
  }
}
