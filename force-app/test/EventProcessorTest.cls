@isTest
private class EventProcessorTest {
    @isTest static void summaryBasic() {
        LDUser user = new LDUser.Builder('abc').build();

        LDValue value1   = LDValue.of('value1');
        LDValue value2   = LDValue.of('value2');
        LDValue value99  = LDValue.of('value99');
        LDValue default1 = LDValue.of('default1');
        LDValue default2 = LDValue.of('default2');
        LDValue default3 = LDValue.of('default3');

        Event.Feature event1 = new Event.Feature(
            'key1', // key
            user, // user
            11, // version
            1, // variation
            value1, // value
            default1, // defaultValue
            null, // reason
            null, // prereqOf
            false, // trackEvents
            null, // debugEventsUntilDate
            false, // debug
            false // unknown
        );

        Event.Feature event2 = new Event.Feature(
            'key1', // key
            user, // user
            11, // version
            2, // variation
            value2, // value
            default1, // defaultValue
            null, // reason
            null, // prereqOf
            false, // trackEvents
            null, // debugEventsUntilDate
            false, // debug
            false // unknown
        );

        Event.Feature event3 = new Event.Feature(
            'key2', // key
            user, // user
            22, // version
            1, // variation
            value99, // value
            default2, // defaultValue
            null, // reason
            null, // prereqOf
            false, // trackEvents
            null, // debugEventsUntilDate
            false, // debug
            false // unknown
        );

        Event.Feature event4 = new Event.Feature(
            'key1', // key
            user, // user
            11, // version
            1, // variation
            value1, // value
            default1, // defaultValue
            null, // reason
            null, // prereqOf
            false, // trackEvents
            null, // debugEventsUntilDate
            false, // debug
            false // unknown
        );

        Event.Feature event5 = new Event.Feature(
            'badkey', // key
            user, // user
            null, // version
            null, // variation
            default3, // value
            default3, // defaultValue
            null, // reason
            null, // prereqOf
            false, // trackEvents
            null, // debugEventsUntilDate
            false, // debug
            true // unknown
        );

        EventProcessor processor = new EventProcessor();

        processor.summarizeFeatureEvent(event1);
        processor.summarizeFeatureEvent(event2);
        processor.summarizeFeatureEvent(event3);
        processor.summarizeFeatureEvent(event4);
        processor.summarizeFeatureEvent(event5);

        Object summaryEvent = processor.buildSummaryEvent();

        String expectedRaw = '{' +
            '"features": {' +
                '"badkey": {' +
                    '"counters": [' +
                        '{' +
                            '"count": 1,' +
                            '"unknown": true,' +
                            '"value": "default3"' +
                        '}' +
                    '],' +
                    '"default": "default3"' +
                '},' +
                '"key1": {' +
                    '"counters": [' +
                        '{' +
                            '"count": 2,' +
                            '"value": "value1",' +
                            '"variation": 1,' +
                            '"version": 11' +
                        '},' +
                        '{' +
                            '"count": 1,' +
                            '"value": "value2",' +
                            '"variation": 2,' +
                            '"version": 11' +
                        '}' +
                    '],' +
                    '"default": "default1"' +
                '},' +
                '"key2": {' +
                    '"counters": [' +
                        '{' +
                            '"count": 1,' +
                            '"value": "value99",' +
                            '"variation": 1,' +
                            '"version": 22' +
                        '}' +
                    '],' +
                    '"default": "default2"' +
                '}' +
            '},' +
            '"kind": "summary"' +
        '}';

        System.assertEquals(summaryEvent, JSON.deserializeUntyped(expectedRaw));
    }
}
