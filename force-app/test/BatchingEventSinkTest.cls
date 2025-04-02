@isTest
private class BatchingEventSinkTest {
  @isTest
  static void eventSinkRespectsMaxEvents() {
    BatchingEventSink sink = new BatchingEventSink(2);

    sink.sinkGeneric('1', '2');
    sink.sinkGeneric('3', '4');
    sink.sinkGeneric('5', '6');
    sink.flush();

    System.assertEquals(2, [SELECT COUNT() FROM EventData__c]);
  }

  @isTest
  static void eventSinkClosingPreventsAdditionalEvents() {
    BatchingEventSink sink = new BatchingEventSink(2);
    sink.close();

    sink.sinkGeneric('1', '2');
    sink.sinkGeneric('3', '4');
    sink.sinkGeneric('5', '6');
    sink.flush();

    System.assertEquals(0, [SELECT COUNT() FROM EventData__c]);
  }
}
