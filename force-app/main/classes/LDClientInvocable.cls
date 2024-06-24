public class LDClientInvocable {

  public class InvocableRequest {
    @InvocableVariable(label='Flag Key' description='Flag Key as defined in LaunchDarkly' required=true)
    public String flagKey;
    @InvocableVariable(label='Flag Type' description='Flag Type corresponding to Flag Key. Valid options are: Boolean, Double, Integer, and String.' required=true)
    public String flagType;
    @InvocableVariable(label='Boolean Fallback' description='Fallback for Boolean Flag type if no variation found from LaunchDarkly' required=false)
    public Boolean booleanFallback;
    @InvocableVariable(label='Double Fallback' description='Fallback for Double (Number) Flag type if no variation found from LaunchDarkly' required=false)
    public Double doubleFallback;
    @InvocableVariable(label='Integer Fallback' description='Fallback for Integer (Number) Flag type if no variation found from LaunchDarkly' required=false)
    public Integer integerFallback;
    @InvocableVariable(label='String Fallback' description='Fallback for String Flag type if no variation found from LaunchDarkly' required=false)
    public String stringFallback;
    @InvocableVariable(label='User custom attributes' description='Key/Value pairs to assign to user context evaluation. Id and Name will be assigned automatically' required=false)
    public List<LDFlowMapKey> userCustomAttributes;
    @InvocableVariable(label='User to be Identified' description='If TRUE, the LDClient.identify method will be called' required=false)
    public Boolean userToBeIdentified;
  }

  public class InvocableResponse {
    @InvocableVariable(label='Flag Key belonging to the Variation' description='' required=true)
    public String flagKey;
    @InvocableVariable(label='Flag Type' description='Flag Type corresponding to Flag Key' required=true)
    public String flagType;
    @InvocableVariable(label='Boolean Variation' description='Variation for Boolean Flag type' required=false)
    public Boolean booleanVariation;
    @InvocableVariable(label='Double Variation' description='Variation for Double (Number) Flag type' required=false)
    public Double doubleVariation;
    @InvocableVariable(label='Integer Variation' description='Variation for Integer (Number) Flag type' required=false)
    public Integer integerVariation;
    @InvocableVariable(label='String Variation' description='Variation for String Flag type' required=false)
    public String stringVariation;

    public InvocableResponse(InvocableRequest request) {
      this.flagKey = request.flagKey;
      this.flagType = request.flagType;
      this.booleanVariation = false;
    }
  }

  @InvocableMethod(label='Get LaunchDarkly Variation' description='Returns the flag variation for a set of Flag keys')
  public static List<InvocableResponse> flagVariation(List<InvocableRequest> requests) {
    LDClient client = new LDClient();
    List<InvocableResponse> results = new List<InvocableResponse>();
    for (InvocableRequest request : requests) {
      LDUser user = buildLDUser(client, request);
      InvocableResponse result = new InvocableResponse(request);
      if (request.flagType != null) {
        switch on request.flagType.toLowerCase() {
          when 'boolean' {
            result.booleanVariation = client.boolVariation(user, request.flagKey, request.booleanFallback != null ? request.booleanFallback : false);
          }
          when 'double' {
            result.doubleVariation = client.doubleVariation(user, request.flagKey, request.doubleFallback);
          }
          when 'integer' {
            result.integerVariation = client.intVariation(user, request.flagKey, request.integerFallback);
          }
          when 'string' {
            result.stringVariation = client.stringVariation(user, request.flagKey, request.stringFallback);
          }
          when else {
          }
        }
      }
      results.add(result);
    }
    return results;
  }

  private static LDUser buildLDUser(LDClient client, InvocableRequest request) {
    Map<String, LDValue>  valueObjectMap = new Map<String, LDValue>();
    if (request.userCustomAttributes != null) {
      for (LDFlowMapKey userAttribute : request.userCustomAttributes) {
        if (userAttribute.valueType != null) {
          switch on userAttribute.valueType.toLowerCase() {
            when 'boolean' {
              if (userAttribute.booleanValue != null) {
                valueObjectMap.put(userAttribute.key, LDValue.of(userAttribute.booleanValue));
              }
            }
            when 'double' {
              if (userAttribute.doubleValue != null) {
                valueObjectMap.put(userAttribute.key, LDValue.of(userAttribute.doubleValue));
              }
            }
            when 'integer' {
              if (userAttribute.integerValue != null) {
                valueObjectMap.put(userAttribute.key, LDValue.of(userAttribute.integerValue));
              }
            }
            when 'string' {
              if (userAttribute.stringValue != null) {
                valueObjectMap.put(userAttribute.key, LDValue.of(userAttribute.stringValue));
              }
            }
            when else {
            }
          }
        }
      }
    }
    LDUser user = new LDUser.Builder(System.UserInfo.getUserId())
      .setName(System.UserInfo.getName())
      .setCustom(LDValueObject.fromMap(valueObjectMap))
      .build();

    if (request.userToBeIdentified == true) {
      client.identify(user);
    }

    return user;
  }
}
