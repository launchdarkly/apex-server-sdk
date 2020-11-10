@RestResource(urlMapping='/store')
global with sharing class StoreREST {
    @HttpGet
    global static String doGet() {
        LDConfig config = new LDConfig.Builder().build();
        LDUser   user   = new LDUser.Builder('user-key').build();
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

        DataStore store = new DataStore();

        store.putAll((Map<String, Object>)JSON.deserializeUntyped(request.requestBody.tostring()));

        return request.requestBody.tostring();
    }
}
