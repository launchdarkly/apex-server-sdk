public class LDConfig {
  private final Boolean allAttributesPrivate;
  private final Integer maxEvents;
  private final Integer ttl;
  private final Boolean batchEvents;
  private final String scopeKey;

  private LDConfig(
    Boolean allAttributesPrivate,
    Integer maxEvents,
    Integer ttl,
    Boolean batchEvents,
    String scopeKey
  ) {
    this.allAttributesPrivate = allAttributesPrivate;
    this.maxEvents = maxEvents;
    this.ttl = ttl;
    this.batchEvents = batchEvents;
    this.scopeKey = scopeKey;
  }

  public Boolean getAllAttributesPrivate() {
    return this.allAttributesPrivate;
  }

  public Integer getMaxEventsInQueue() {
    return this.maxEvents;
  }

  public Integer getCacheTtl() {
    return this.ttl;
  }

  public Boolean getBatchEvents() {
    return this.batchEvents;
  }

  public String getScopeKey() {
    return this.scopeKey;
  }

  public class Builder {
    private Boolean allAttributesPrivate;
    private Integer maxEvents;
    private Integer ttl;
    private Boolean batchEvents;
    private String scopeKey;

    public Builder() {
      this.allAttributesPrivate = false;
      this.maxEvents = 1000;
      this.ttl = null;
      this.batchEvents = false;
      this.scopeKey = null;
    }

    public Builder setAllAttributesPrivate(Boolean allAttributesPrivate) {
      if (allAttributesPrivate == null) {
        this.allAttributesPrivate = false;
      } else {
        this.allAttributesPrivate = allAttributesPrivate;
      }

      return this;
    }

    public Builder setMaxEventsInQueue(Integer maxEvents) {
      if (maxEvents == null) {
        this.maxEvents = 1000;
      } else {
        this.maxEvents = maxEvents;
      }

      return this;
    }

    public Builder setCacheTtl(Integer ttl) {
      this.ttl = ttl;
      return this;
    }

    public Builder setBatchEvents(Boolean batchEvents) {
      this.batchEvents = batchEvents;
      return this;
    }

    // The LaunchDarkly scope this client reads and writes. It must match the scope key
    // configured on the bridge that populates this org, or evaluation finds no flag data and
    // every variation call returns its fallback. Leaving it unset scopes the client to
    // records carrying no scope, which is the behavior from before scoping existed.
    public Builder setScopeKey(String scopeKey) {
      // The bridge trims the key it sends, and it treats a blank key as an absent one.
      // Normalize the same way here so the two sides agree. An untrimmed key matches no
      // records at all, and every variation call then returns its fallback.
      if (String.isBlank(scopeKey)) {
        this.scopeKey = null;
      } else {
        this.scopeKey = scopeKey.trim();
      }

      return this;
    }

    public LDConfig build() {
      return new LDConfig(
        this.allAttributesPrivate,
        this.maxEvents,
        this.ttl,
        this.batchEvents,
        this.scopeKey
      );
    }
  }
}
