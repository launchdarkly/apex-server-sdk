@RestResource(urlMapping='/store')
global with sharing class StoreREST {
  @HttpGet
  global static String doGet() {
    LDConfig config = new LDConfig.Builder()
      .setScopeKey(ScopeHeader.read(RestContext.request, EventREST.SCOPE_HEADER))
      .build();
    LDUser user = new LDUser.Builder('user-key').build();
    LDClient client = new LDClient(config);

    Boolean result = client.boolVariation(user, 'flag-52', false);

    if (result) {
      return 'enabled';
    } else {
      return 'disabled';
    }
  }

  @HttpPost
  global static String doPost() {
    RestRequest request = RestContext.request;

    // The scope arrives as a header, never as a key in the body: the bridge forwards
    // LaunchDarkly's payload verbatim and putAll treats every top-level key as a kind,
    // casting its value to a Map, so a sibling key would throw in older orgs.
    DataStore store = new DataStore(ScopeHeader.read(request, EventREST.SCOPE_HEADER));

    store.putAll((Map<String, Object>) JSON.deserializeUntyped(request.requestBody.tostring()));

    return request.requestBody.tostring();
  }
}
