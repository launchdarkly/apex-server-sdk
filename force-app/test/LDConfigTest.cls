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

  @isTest
  static void getDefaultScopeKeySetting() {
    LDConfig config = new LDConfig.Builder().build();

    System.assertEquals(config.getScopeKey(), null);
  }

  @isTest
  static void setScopeKeySetting() {
    LDConfig config = new LDConfig.Builder().setScopeKey('gps').build();

    System.assertEquals(config.getScopeKey(), 'gps');
  }

  @isTest
  static void setScopeKeyTrimsSurroundingWhitespace() {
    System.assertEquals(new LDConfig.Builder().setScopeKey(' gps ').build().getScopeKey(), 'gps');
    System.assertEquals(new LDConfig.Builder().setScopeKey('gps ').build().getScopeKey(), 'gps');
    System.assertEquals(new LDConfig.Builder().setScopeKey(' gps').build().getScopeKey(), 'gps');
  }

  @isTest
  static void setScopeKeyTreatsBlankAsUnset() {
    System.assertEquals(new LDConfig.Builder().setScopeKey(null).build().getScopeKey(), null);
    System.assertEquals(new LDConfig.Builder().setScopeKey('').build().getScopeKey(), null);
    System.assertEquals(new LDConfig.Builder().setScopeKey('   ').build().getScopeKey(), null);
  }

  @isTest
  static void setScopeKeyKeepsLetterCase() {
    // LaunchDarkly scope keys are case sensitive. The setter must not fold the case, even
    // though Salesforce matches the stored field without regard to case.
    System.assertEquals(new LDConfig.Builder().setScopeKey('MyScope').build().getScopeKey(), 'MyScope');
    System.assertEquals(new LDConfig.Builder().setScopeKey(' MyScope ').build().getScopeKey(), 'MyScope');
  }
}
