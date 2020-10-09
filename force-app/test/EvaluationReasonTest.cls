@isTest
private class EvaluationReasonTest {
    @isTest static void basicOffRep() {
        EvaluationReason reason = EvaluationReason.off();
        String expectedRaw = '{"kind": "OFF"}';
        System.assertEquals(reason.toGeneric(), JSON.deserializeUntyped(expectedRaw));
    }

    @isTest static void basicErrorRep() {
        EvaluationReason reason = EvaluationReason.exception();
        String expectedRaw = '{"kind": "ERROR", "errorKind": "EXCEPTION_THROWN"}';
        System.assertEquals(reason.toGeneric(), JSON.deserializeUntyped(expectedRaw));
    }

    @isTest static void basicPrereqFailedRep() {
        EvaluationReason reason = EvaluationReason.prerequisiteFailed('abc');
        String expectedRaw = '{"kind": "PREREQUISITE_FAILED", "prerequisiteKey": "abc"}';
        System.assertEquals(reason.toGeneric(), JSON.deserializeUntyped(expectedRaw));
    }

    @isTest static void basicRuleMatchRep() {
        EvaluationReason reason = EvaluationReason.ruleMatch(2, 'xyz');
        String expectedRaw = '{"kind": "RULE_MATCH", "ruleId": "xyz", "ruleIndex": 2}';
        System.assertEquals(reason.toGeneric(), JSON.deserializeUntyped(expectedRaw));
    }
}
