@isTest
private class LDConfigTest {
  @isTest
  static void getDefaultAllAttributesPrivateSetting() {
    LDConfig config = new LDConfig.Builder().build();

    System.assertEquals(config.getAllAttributesPrivate(), false);
  }

  @isTest
  static void getDefaultMaxEventsInQueueSetting() {
    LDConfig config = new LDConfig.Builder().build();

    System.assertEquals(config.getMaxEventsInQueue(), 1000);
  }

  @isTest
  static void setAllAttributesPrivateSettingNull() {
    LDConfig.Builder builder = new LDConfig.Builder();

    LDConfig config = builder.setAllAttributesPrivate(null).build();

    System.assertEquals(config.getAllAttributesPrivate(), false);
  }

  @isTest
  static void setAllAttributesPrivateSettingTrue() {
    LDConfig.Builder builder = new LDConfig.Builder();

    LDConfig config = builder.setAllAttributesPrivate(true).build();

    System.assertEquals(config.getAllAttributesPrivate(), true);
  }

  @isTest
  static void settMaxEventsInQueueSettingNull() {
    LDConfig.Builder builder = new LDConfig.Builder();

    LDConfig config = builder.setMaxEventsInQueue(null).build();

    System.assertEquals(config.getMaxEventsInQueue(), 1000);
  }

  @isTest
  static void settMaxEventsInQueueSetting() {
    LDConfig.Builder builder = new LDConfig.Builder();

    LDConfig config = builder.setMaxEventsInQueue(5000).build();

    System.assertEquals(config.getMaxEventsInQueue(), 5000);
  }
}
