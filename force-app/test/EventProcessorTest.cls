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

        LDEvent.Feature event1 = new LDEvent.Feature(
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
            false, // unknown
            1, // now
            false // allAttributesPrivate
        );

        LDEvent.Feature event2 = new LDEvent.Feature(
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
            false, // unknown
            2, // now
            false // allAttributesPrivate
        );

        LDEvent.Feature event3 = new LDEvent.Feature(
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
            false, // unknown
            3, // now
            false // allAttributesPrivate
        );

        LDEvent.Feature event4 = new LDEvent.Feature(
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
            false, // unknown
            4, // now
            false // allAttributesPrivate
        );

        LDEvent.Feature event5 = new LDEvent.Feature(
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
            true, // unknown
            5, // now
            false // allAttributesPrivate
        );

        EventProcessor processor = new EventProcessor(new GetTimeMock());

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
            '"kind": "summary",' +
            '"startDate": 1,' +
            '"endDate": 2' +
        '}';

        System.assertEquals(
            JSON.deserializeUntyped(JSON.serialize(summaryEvent)),
            JSON.deserializeUntyped(expectedRaw)
        );
    }

    @isTest static void processFeatureEvent() {
        LDUser  user  = new LDUser.Builder('abc').build();
        LDValue value = LDValue.of('value');

        LDEvent.Feature event = new LDEvent.Feature(
            'key1', // key
            user, // user
            11, // version
            1, // variation
            value, // value
            value, // defaultValue
            null, // reason
            null, // prereqOf
            false, // trackEvents
            null, // debugEventsUntilDate
            false, // debug
            false, // unknown
            6, // now
            false // allAttributesPrivate
        );

        EventProcessor processor = new EventProcessor(new GetTimeMock());

        processor.processFeatureEvent(event);
    }
    
    @isTest static void withoutEventsBundleIsEmpty() {
        EventProcessor processor = new EventProcessor(new GetTimeMock());
        
        Object bundle = processor.buildEventBundle();
        
        List<Object> expected = new List<Object>();
        
        System.assertEquals(bundle, (Object)expected);
    }
    
    @isTest static void eventBundleIncludesProcessed() {
        EventProcessor processor = new EventProcessor(new GetTimeMock());
        // does not actually matter what the value is
        processor.addProcessedEvent(52);
        
        Object bundle = processor.buildEventBundle();

        List<Object> expected = new List<Object>();
        expected.add(52);
        
        System.assertEquals(bundle, (Object)expected);
    }
    
    @isTest static void eventBundleIncludesSummary() {
        EventProcessor processor = new EventProcessor(new GetTimeMock());

        LDEvent.Feature event1 = new LDEvent.Feature(
            'key1', // key
            new LDUser.Builder('abc').build(), // user
            11, // version
            1, // variation
            LDValue.of('value1'), // value
            LDValue.of('default1'), // defaultValue
            null, // reason
            null, // prereqOf
            false, // trackEvents
            null, // debugEventsUntilDate
            false, // debug
            false, // unknown
            1, // now
            false // allAttributesPrivate
        );
        
        processor.summarizeFeatureEvent(event1);
        
        String expectedRaw = '[{' +
            '"features": {' +
                '"key1": {' +
                    '"counters": [' +
                        '{' +
                            '"count": 1,' +
                            '"value": "value1",' +
                            '"variation": 1,' +
                            '"version": 11' +
                        '}' +
                    '],' +
                    '"default": "default1"' +
                '}' +
            '},' +
            '"kind": "summary",' +
            '"startDate": 1,' +
            '"endDate": 2' +
        '}]';
        
        Object bundle = processor.buildEventBundle();

        System.assertEquals(
            JSON.deserializeUntyped(JSON.serialize(bundle)),
            JSON.deserializeUntyped(expectedRaw)
        );
    }
    
    @isTest static void trackFeatureEventIncluded() {
        EventProcessor processor = new EventProcessor(new GetTimeMock());

        LDEvent.Feature event1 = new LDEvent.Feature(
            'key1', // key
            new LDUser.Builder('abc').build(), // user
            11, // version
            1, // variation
            LDValue.of('value1'), // value
            LDValue.of('default1'), // defaultValue
            null, // reason
            null, // prereqOf
            true, // trackEvents
            null, // debugEventsUntilDate
            false, // debug
            false, // unknown
            1, // now
            false // allAttributesPrivate
        );
        
        processor.processFeatureEvent(event1);
        
        String expectedRaw = '[' +
            '{' +
                '"kind": "feature",' +
                '"key": "key1",' +
                '"creationDate": 1,' +
                '"default": "default1",' +
                '"value": "value1",' +
                '"variation": 1,' +
                '"version": 11,' +
                '"user": {"key":"abc"}' +
            '},' +
            '{' +
                '"features": {' +
                    '"key1": {' +
                        '"counters": [' +
                            '{' +
                                '"count": 1,' +
                                '"value": "value1",' +
                                '"variation": 1,' +
                                '"version": 11' +
                            '}' +
                        '],' +
                        '"default": "default1"' +
                    '}' +
                '},' +
                '"kind": "summary",' +
                '"startDate": 1,' +
                '"endDate": 2' +
            '}' +
        ']';
        
        Object bundle = processor.buildEventBundle();
        
        // fix errors with numeric types not matching
        Object bundleIso = JSON.deserializeUntyped(JSON.serialize(bundle));

        System.assertEquals(bundleIso, JSON.deserializeUntyped(expectedRaw));
    }
}
