@isTest
private class LDClientInvocableTest {

  @isTest
  static void basicVariation() {
    LDClientInvocable.InvocableRequest requestData = new LDClientInvocable.InvocableRequest();
    requestData.flagKey = 'fakeFlag';
    requestData.flagType = 'Boolean';
    requestData.booleanFallback = false;
    requestData.userCustomAttributes = new List<LDFlowMapKey>();

    LDFlowMapKey booleanMapKey = new LDFlowMapKey();
    booleanMapKey.key = 'booleanKey';
    booleanMapKey.valueType = 'Boolean';
    booleanMapKey.booleanValue = false;
    requestData.userCustomAttributes.add(booleanMapKey);

    LDFlowMapKey doubleMapKey = new LDFlowMapKey();
    doubleMapKey.key = 'doubleKey';
    doubleMapKey.valueType = 'Double';
    doubleMapKey.doubleValue = 25.48;
    requestData.userCustomAttributes.add(doubleMapKey);

    LDFlowMapKey integerMapKey = new LDFlowMapKey();
    integerMapKey.key = 'integerKey';
    integerMapKey.valueType = 'Integer';
    integerMapKey.integerValue = 25;
    requestData.userCustomAttributes.add(integerMapKey);

    LDFlowMapKey stringMapKey = new LDFlowMapKey();
    stringMapKey.key = 'stringKey';
    stringMapKey.valueType = 'String';
    stringMapKey.stringValue = 'string';
    requestData.userCustomAttributes.add(stringMapKey);

    requestData.userToBeIdentified = true;

    LDClientInvocable.InvocableResponse responseData = LDClientInvocable.flagVariation(new List<LDClientInvocable.InvocableRequest>{requestData})[0];

    System.assertEquals(requestData.flagKey, responseData.flagKey, 'Response flag key should match the request flag key');
    System.assertEquals(requestData.flagType, responseData.flagType, 'Response flag key should match the request flag key');
    System.assertEquals(false, responseData.booleanVariation, 'Response Boolean Variation should be FALSE to match the fallback value since the flag does not exist');
  }


  @isTest
  static void intVariation() {
    LDClientInvocable.InvocableRequest requestData = new LDClientInvocable.InvocableRequest();
    requestData.flagKey = 'fakeFlag';
    requestData.flagType = 'Integer';
    requestData.integerFallback = 2024;
    requestData.userCustomAttributes = new List<LDFlowMapKey>();
    requestData.userToBeIdentified = true;

    LDClientInvocable.InvocableResponse responseData = LDClientInvocable.flagVariation(new List<LDClientInvocable.InvocableRequest>{requestData})[0];

    System.assertEquals(requestData.flagKey, responseData.flagKey, 'Response flag key should match the request flag key');
    System.assertEquals(requestData.flagType, responseData.flagType, 'Response flag key should match the request flag key');
    System.assertEquals(2024, responseData.integerVariation, 'Response Integer Variation should be 2024 to match the fallback value since the flag does not exist');
  }

  @isTest
  static void doubleVariation() {
    LDClientInvocable.InvocableRequest requestData = new LDClientInvocable.InvocableRequest();
    requestData.flagKey = 'fakeFlag';
    requestData.flagType = 'Double';
    requestData.doubleFallback = 2024.06;
    requestData.userCustomAttributes = new List<LDFlowMapKey>();
    requestData.userToBeIdentified = true;

    LDClientInvocable.InvocableResponse responseData = LDClientInvocable.flagVariation(new List<LDClientInvocable.InvocableRequest>{requestData})[0];

    System.assertEquals(requestData.flagKey, responseData.flagKey, 'Response flag key should match the request flag key');
    System.assertEquals(requestData.flagType, responseData.flagType, 'Response flag key should match the request flag key');
    System.assertEquals(2024.06, responseData.doubleVariation, 'Response Double Variation should be 2024.06 to match the fallback value since the flag does not exist');
  }

  @isTest
  static void stringVariation() {
    LDClientInvocable.InvocableRequest requestData = new LDClientInvocable.InvocableRequest();
    requestData.flagKey = 'fakeFlag';
    requestData.flagType = 'String';
    requestData.stringFallback = 'test string';
    requestData.userCustomAttributes = new List<LDFlowMapKey>();
    requestData.userToBeIdentified = true;

    LDClientInvocable.InvocableResponse responseData = LDClientInvocable.flagVariation(new List<LDClientInvocable.InvocableRequest>{requestData})[0];

    System.assertEquals(requestData.flagKey, responseData.flagKey, 'Response flag key should match the request flag key');
    System.assertEquals(requestData.flagType, responseData.flagType, 'Response flag key should match the request flag key');
    System.assertEquals('test string', responseData.stringVariation, 'Response String Variation should be \'test string\' to match the fallback value since the flag does not exist');
  }
}
