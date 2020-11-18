public class EventSink implements EventSinkInterface {
    Integer maxEvents;

    public EventSink(Integer maxEvents) {
        System.assertNotEquals(maxEvents, null);

        this.maxEvents = maxEvents;
    }

    public void sinkIdentify(Event.Identify event) {
        this.sinkGeneric('identify', JSON.serialize(event.toGeneric()));
    }

    public void sinkCustom(Event.Custom event) {
        this.sinkGeneric('custom', JSON.serialize(event.toGeneric()));
    }

    public void sinkFeature(Event.Feature event) {
        this.sinkGeneric('feature', JSON.serialize(event.toGeneric()));
    }
    
    public void sinkGeneric(String kind, String raw) {
        Integer count = [SELECT COUNT() FROM EventData__c];
        
        if (count >= this.maxEvents) {
            return;
        }

        EventData__c record = new EventData__c();
        record.Kind__c = kind;
        record.Raw__c  = raw;

        insert record;
    }
}
