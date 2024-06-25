// Used as an Apex-Defined Variable to allow map-like entry for user custom attributes
public class LDFlowMapKey {
  @AuraEnabled
  public string key;
  @AuraEnabled
  public string valueType;
  @AuraEnabled
  public Boolean booleanValue;
  @AuraEnabled
  public Double doubleValue;
  @AuraEnabled
  public Integer integerValue;
  @AuraEnabled
  public string stringValue;
  
  public LDFlowMapKey(){}
}