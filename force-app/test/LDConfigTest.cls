/**
 * This class contains unit tests for validating the behavior of Apex classes
 * and triggers.
 *
 * Unit tests are class methods that verify whether a particular piece
 * of code is working properly. Unit test methods take no arguments,
 * commit no data to the database, and are flagged with the testMethod
 * keyword in the method definition.
 *
 * All test methods in an org are executed whenever Apex code is deployed
 * to a production org to confirm correctness, ensure code
 * coverage, and prevent regressions. All Apex classes are
 * required to have at least 75% code coverage in order to be deployed
 * to a production org. In addition, all triggers must have some code coverage.
 *
 * The @isTest class annotation indicates this class only contains test
 * methods. Classes defined with the @isTest annotation do not count against
 * the org size limit for all Apex scripts.
 *
 * See the Apex Language Reference for more information about Testing and Code Coverage.
 */
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
