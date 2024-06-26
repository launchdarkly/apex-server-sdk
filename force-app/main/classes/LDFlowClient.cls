// Used as an Apex-Defined Variable to allow LDClient persistance across variation calls
public class LDFlowClient {
  @AuraEnabled
  public LDClient client;
  // clientName only included so that LDFlowClient is visible as an Apex-Defined Variable in the Flow
  @AuraEnabled
  public String clientName;
  
  public LDFlowClient(){}
}