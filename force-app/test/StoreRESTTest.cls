@isTest
private class StoreRESTTest {
  @isTest
  static void doGetDisabled() {
    String result = StoreREST.doGet();

    System.assertEquals(result, 'disabled');
  }

  @isTest
  static void doPost() {
    String raw =
      '{"flags":' +
      '{' +
      '"hello": ' +
      '{' +
      '"version": 52, ' +
      '"key": "hello", ' +
      '"on": false, ' +
      '"offVariation": 0, ' +
      '"salt": "abc123", ' +
      '"fallthrough": ' +
      '{' +
      '"variation": 0' +
      '},' +
      '"variations": [true]' +
      '}' +
      '}' +
      '}';

    RestRequest request = new RestRequest();

    request.requestBody = Blob.valueOf(raw);

    RestContext.request = request;

    String result = StoreREST.doPost();

    System.assertEquals(result, raw, result);
  }
}
