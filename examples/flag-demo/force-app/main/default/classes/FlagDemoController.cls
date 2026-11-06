/**
 * Controller for the FlagDemo Visualforce page.
 *
 * Evaluates one featured flag for a user, with the reason the SDK gives for the result,
 * and lists every flag the bridge has mirrored into this org with its value for the same
 * user. Each evaluation writes a feature event to EventData__c, which the bridge drains
 * and forwards to LaunchDarkly, so reloading the page exercises both directions.
 */
public with sharing class FlagDemoController {
  public String userKey { get; set; }
  public String flagKey { get; set; }
  // The scope key the bridge was started with, as LD_SCOPE_KEY. Blank when the bridge
  // has none. The two must agree, or every evaluation returns its fallback.
  public String scopeKey { get; set; }

  public String flagValue { get; private set; }
  public String reason { get; private set; }
  public Integer variationIndex { get; private set; }
  public String evaluatedAt { get; private set; }
  public List<FlagRow> allFlags { get; private set; }

  public class FlagRow {
    public String key { get; private set; }
    public String value { get; private set; }

    public FlagRow(String key, String value) {
      this.key = key;
      this.value = value;
    }
  }

  public FlagDemoController() {
    userKey = String.isBlank(ApexPages.currentPage().getParameters().get('user'))
      ? 'demo-user'
      : ApexPages.currentPage().getParameters().get('user');
    flagKey = String.isBlank(ApexPages.currentPage().getParameters().get('flag'))
      ? 'test-flag'
      : ApexPages.currentPage().getParameters().get('flag');
    scopeKey = ApexPages.currentPage().getParameters().get('scope');
    allFlags = new List<FlagRow>();
    // Not evaluated here. Each evaluation writes an event row, and Visualforce forbids
    // DML in a constructor; the page's load action calls evaluate instead.
  }

  // Bound to the page's load action and its button. Returning null re-renders the page.
  public PageReference evaluate() {
    LDConfig.Builder config = new LDConfig.Builder();
    if (String.isNotBlank(scopeKey)) {
      config.setScopeKey(scopeKey.trim());
    }
    LDClient client = new LDClient(config.build());
    LDUser user = new LDUser.Builder(userKey).build();

    // jsonVariation accepts a flag of any type, so the demo does not have to know
    // whether the featured flag is a boolean, a string, or a number.
    LDClient.EvaluationDetail details = new LDClient.EvaluationDetail();
    LDValue value = client.jsonVariation(user, flagKey, LDValue.of('(fallback)'), details);
    flagValue = JSON.serialize(value.toGeneric());
    variationIndex = details.getVariationIndex();
    EvaluationReason evaluationReason = details.getReason();
    reason = evaluationReason == null
      ? 'none'
      : evaluationReason.kindToString(evaluationReason.getKind());

    Map<String, LDValue> flags = client.allFlags(user);
    List<String> keys = new List<String>(flags.keySet());
    keys.sort();
    allFlags = new List<FlagRow>();
    for (String key : keys) {
      allFlags.add(new FlagRow(key, JSON.serialize(flags.get(key).toGeneric())));
    }

    client.close();
    evaluatedAt = Datetime.now().format('yyyy-MM-dd HH:mm:ss z');

    return null;
  }
}
