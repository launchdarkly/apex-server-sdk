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
  static void getDefaultProjectKeySetting() {
    LDConfig config = new LDConfig.Builder().build();

    System.assertEquals(config.getProjectKey(), null);
  }

  @isTest
  static void setProjectKeySetting() {
    LDConfig config = new LDConfig.Builder().setProjectKey('gps').build();

    System.assertEquals(config.getProjectKey(), 'gps');
  }

  @isTest
  static void setProjectKeyTrimsSurroundingWhitespace() {
    System.assertEquals(new LDConfig.Builder().setProjectKey(' gps ').build().getProjectKey(), 'gps');
    System.assertEquals(new LDConfig.Builder().setProjectKey('gps ').build().getProjectKey(), 'gps');
    System.assertEquals(new LDConfig.Builder().setProjectKey(' gps').build().getProjectKey(), 'gps');
  }

  @isTest
  static void setProjectKeyTreatsBlankAsUnset() {
    System.assertEquals(new LDConfig.Builder().setProjectKey(null).build().getProjectKey(), null);
    System.assertEquals(new LDConfig.Builder().setProjectKey('').build().getProjectKey(), null);
    System.assertEquals(new LDConfig.Builder().setProjectKey('   ').build().getProjectKey(), null);
  }

  @isTest
  static void setProjectKeyKeepsLetterCase() {
    // LaunchDarkly project keys are case sensitive. The setter must not fold the case, even
    // though Salesforce matches the stored field without regard to case.
    System.assertEquals(new LDConfig.Builder().setProjectKey('MyProject').build().getProjectKey(), 'MyProject');
    System.assertEquals(new LDConfig.Builder().setProjectKey(' MyProject ').build().getProjectKey(), 'MyProject');
  }
}
