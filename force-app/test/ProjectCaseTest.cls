// Pins the one thing this SDK guarantees about project keys that differ only by letter case:
// an unsupported key never destroys a supported project's data.
//
// Salesforce matches text without regard to case, so a filter for project 'alpha' also returns
// the records of project 'Alpha'. Reads are deliberately left alone -- which record an
// unsupported key resolves to is undefined. Deleting and draining are not, because they remove
// data, and a typo in one bridge's project key must not wipe out another project.
@isTest
private class ProjectCaseTest {
  private static Map<String, Object> flagPayload(Integer version) {
    return (Map<String, Object>) JSON.deserializeUntyped(
      '{"flags":{"shared":{"version":' + version + ',"key":"shared","on":false,' +
        '"variations":[true],"offVariation":0,"fallthrough":{"variation":0},' +
        '"prerequisites":[],"targets":[],"rules":[],"salt":"s"}},"segments":{}}'
    );
  }

  // A push for 'alpha' must leave 'Alpha' alone, in both stores.
  @isTest
  static void aPushDoesNotDeleteACollidingProject() {
    new DataStore('Alpha').putAll(flagPayload(1));
    new DataStore('alpha').putAll(flagPayload(2));

    System.assertEquals(2, [SELECT COUNT() FROM VersionedData__c]);
  }

  @isTest
  static void aCachedPushDoesNotDeleteACollidingProject() {
    new CachingDataStore(30000, new GetTimeImpl(), 'Alpha').putAll(flagPayload(1));
    new CachingDataStore(30000, new GetTimeImpl(), 'alpha').putAll(flagPayload(2));

    System.assertEquals(2, [SELECT COUNT() FROM VersionedData__c]);
  }

  // The first push of a new project finds no records of its own. It must still not fall back to
  // deleting the records of the project whose key differs only by case.
  @isTest
  static void aFirstPushDoesNotDeleteACollidingProject() {
    new DataStore('Alpha').putAll(flagPayload(1));

    System.assertEquals(1, [SELECT COUNT() FROM VersionedData__c]);

    new DataStore('alpha').putAll(flagPayload(2));

    System.assertEquals(1, [SELECT COUNT() FROM VersionedData__c WHERE Project__c = 'Alpha' AND Version__c = 1]);
  }

  // A push must still replace its own project's records, which is the behavior the guard has to
  // preserve.
  @isTest
  static void aPushStillReplacesItsOwnRecords() {
    new DataStore('Alpha').putAll(flagPayload(1));
    new DataStore('Alpha').putAll(flagPayload(2));

    System.assertEquals(1, [SELECT COUNT() FROM VersionedData__c]);
    System.assertEquals(2, new DataStore('Alpha').getVersioned('shared', 'flags').Version__c);
  }

  // Records that carry no project are their own scope, and a push for a named project must not
  // delete them. This is the state an org is in before it configures a project at all.
  @isTest
  static void aPushDoesNotDeleteRecordsWithNoProject() {
    new DataStore(null).putAll(flagPayload(1));
    new DataStore('Alpha').putAll(flagPayload(2));

    System.assertEquals(2, [SELECT COUNT() FROM VersionedData__c]);
    System.assertEquals(1, new DataStore(null).getVersioned('shared', 'flags').Version__c);
  }

  // When both casings have events of their own, each bridge drains only its own.
  @isTest
  static void aDrainDoesNotTakeACollidingProjectsEvents() {
    new EventSink(1000, 'Alpha').sinkGeneric('custom', '{}');
    new EventSink(1000, 'alpha').sinkGeneric('custom', '{}');

    EventREST.prepareEvents('Alpha');

    List<EventData__c> left = [SELECT Project__c FROM EventData__c];
    System.assertEquals(1, left.size());
    System.assertEquals('alpha', left.get(0).Project__c);
  }

  // A bridge whose project key differs in case from the Apex client's still drains, because
  // nothing else drains those events. Refer to CaseMatch.scopeEventsToProject.
  @isTest
  static void aDrainFallsBackWhenNoEventsMatchExactly() {
    new EventSink(1000, 'Alpha').sinkGeneric('custom', '{}');

    EventREST.prepareEvents('alpha');

    System.assertEquals(0, [SELECT COUNT() FROM EventData__c]);
  }

  @isTest
  static void aNullProjectIsItsOwnScope() {
    System.assertEquals(true, CaseMatch.sameProject(null, null));
    System.assertEquals(false, CaseMatch.sameProject(null, 'alpha'));
    System.assertEquals(false, CaseMatch.sameProject('alpha', null));
    System.assertEquals(true, CaseMatch.sameProject('alpha', 'alpha'));
    System.assertEquals(false, CaseMatch.sameProject('Alpha', 'alpha'));
  }
}
