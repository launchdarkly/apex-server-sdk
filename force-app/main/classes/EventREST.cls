@RestResource(urlMapping='/event')
global with sharing class EventREST {
    @HttpGet
    global static void doGet() {
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(EventREST.prepareEvents()));
    }
    
    public static Object prepareEvents() {
        EventProcessor processor = new EventProcessor(new GetTimeImpl());
        
        List<EventData__c> events = [SELECT Kind__c, Raw__c FROM EventData__c];
        
        for (EventData__c event : events) {
            switch on event.Kind__c {
                when 'feature' {
                    Object parsed = (Object)JSON.deserializeUntyped(event.Raw__c);
                    LDEvent.Feature featureEvent = new LDEvent.Feature(parsed);
                    processor.processFeatureEvent(featureEvent);
                }
                when else {
                    processor.addProcessedEvent(JSON.deserializeUntyped(event.Raw__c));
                }
            }
        }
        
        delete events;

        return processor.buildEventBundle();
    }
}
