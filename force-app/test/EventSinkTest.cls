@isTest
private class EventSinkTest {
  @isTest
  static void eventSinkRespectsMaxEvents() {
    EventSink sink = new EventSink(2);

    sink.sinkGeneric('1', '2');
    sink.sinkGeneric('3', '4');
    sink.sinkGeneric('5', '6');

    System.assertEquals(2, [SELECT COUNT() FROM EventData__c]);
  }

  @isTest
  static void eventSinkClosingMeansNothing() {
    EventSink sink = new EventSink(2);
    sink.close();

    sink.sinkGeneric('1', '2');

    System.assertEquals(1, [SELECT COUNT() FROM EventData__c]);
  }
}
