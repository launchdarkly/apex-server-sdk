@isTest
private class VersionedDataTest {
  @isTest
  static void versionData() {
    string kind = 'experiment';
    Map<String, Object> obj = new Map<String, Object>();

    obj.put('version', 1);
    obj.put('key', 'test-key');
    VersionedData versionData = new VersionedData(kind, obj);

    System.assertEquals(versionData.getKey(), obj.get('key'));
    System.assertEquals(versionData.getVersion(), obj.get('version'));
    System.assertEquals(versionData.getKind(), kind);
  }
}
