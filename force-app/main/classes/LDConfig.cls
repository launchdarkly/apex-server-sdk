public class LDConfig {
  private final Boolean allAttributesPrivate;
  private final Integer maxEvents;
  private final Integer ttl;
  private final Boolean batchEvents;

  private LDConfig(Boolean allAttributesPrivate, Integer maxEvents, Integer ttl, Boolean batchEvents) {
    this.allAttributesPrivate = allAttributesPrivate;
    this.maxEvents = maxEvents;
    this.ttl = ttl;
    this.batchEvents = batchEvents;
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

  public class Builder {
    private Boolean allAttributesPrivate;
    private Integer maxEvents;
    private Integer ttl;
    private Boolean batchEvents;

    public Builder() {
      this.allAttributesPrivate = false;
      this.maxEvents = 1000;
      this.ttl = null;
      this.batchEvents = false;
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

    public LDConfig build() {
      return new LDConfig(this.allAttributesPrivate, this.maxEvents, this.ttl, this.batchEvents);
    }
  }
}
