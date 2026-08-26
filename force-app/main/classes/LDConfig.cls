public class LDConfig {
  private final Boolean allAttributesPrivate;
  private final Integer maxEvents;
  private final Integer ttl;
  private final Boolean batchEvents;
  private final String projectKey;

  private LDConfig(
    Boolean allAttributesPrivate,
    Integer maxEvents,
    Integer ttl,
    Boolean batchEvents,
    String projectKey
  ) {
    this.allAttributesPrivate = allAttributesPrivate;
    this.maxEvents = maxEvents;
    this.ttl = ttl;
    this.batchEvents = batchEvents;
    this.projectKey = projectKey;
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

  public String getProjectKey() {
    return this.projectKey;
  }

  public class Builder {
    private Boolean allAttributesPrivate;
    private Integer maxEvents;
    private Integer ttl;
    private Boolean batchEvents;
    private String projectKey;

    public Builder() {
      this.allAttributesPrivate = false;
      this.maxEvents = 1000;
      this.ttl = null;
      this.batchEvents = false;
      this.projectKey = null;
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

    // The LaunchDarkly project this client reads and writes. It must match the project key
    // configured on the bridge that populates this org, or evaluation finds no flag data and
    // every variation call returns its fallback. Leaving it unset scopes the client to
    // records carrying no project, which is the pre-multi-project behavior.
    public Builder setProjectKey(String projectKey) {
      // The bridge trims the key it sends, and it treats a blank key as an absent one.
      // Normalize the same way here so the two sides agree. An untrimmed key matches no
      // records at all, and every variation call then returns its fallback.
      if (String.isBlank(projectKey)) {
        this.projectKey = null;
      } else {
        this.projectKey = projectKey.trim();
      }

      return this;
    }

    public LDConfig build() {
      return new LDConfig(
        this.allAttributesPrivate,
        this.maxEvents,
        this.ttl,
        this.batchEvents,
        this.projectKey
      );
    }
  }
}
