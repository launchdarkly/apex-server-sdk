public class LDUser {
  private final String key;
  private final Boolean anonymous;
  private final String ip;
  private final String firstName;
  private final String lastName;
  private final String email;
  private final String name;
  private final String avatar;
  private final String country;
  private final String secondary;
  private final LDValueObject custom;
  private final Set<String> privateAttributeNames;

  private LDUser(
    String key,
    Boolean anonymous,
    String ip,
    String firstName,
    String lastName,
    String email,
    String name,
    String avatar,
    String country,
    String secondary,
    LDValueObject custom,
    Set<String> privateAttributeNames
  ) {
    this.key = key;
    this.anonymous = anonymous;
    this.ip = ip;
    this.firstName = firstName;
    this.lastName = lastName;
    this.email = email;
    this.name = name;
    this.avatar = avatar;
    this.country = country;
    this.secondary = secondary;
    this.custom = custom;
    this.privateAttributeNames = privateAttributeNames;
  }

  public String getKey() {
    return this.key;
  }

  public Boolean getAnonymous() {
    return this.anonymous;
  }

  public String getIP() {
    return this.ip;
  }

  public String getFirstName() {
    return this.firstName;
  }

  public String getLastName() {
    return this.lastName;
  }

  public String getEmail() {
    return this.email;
  }

  public String getName() {
    return this.name;
  }

  public String getAvatar() {
    return this.avatar;
  }

  public String getCountry() {
    return this.country;
  }

  public String getSecondary() {
    return this.secondary;
  }

  public LDValueObject getCustom() {
    return this.custom;
  }

  public LDValue getAttribute(String attribute) {
    switch on attribute {
      when 'key' {
        return LDValue.of(this.key);
      }
      when 'anonymous' {
        return LDValue.of(this.anonymous);
      }
      when 'ip' {
        return LDValue.of(this.ip);
      }
      when 'firstName' {
        return LDValue.of(this.firstName);
      }
      when 'lastName' {
        return LDValue.of(this.lastName);
      }
      when 'email' {
        return LDValue.of(this.email);
      }
      when 'name' {
        return LDValue.of(this.name);
      }
      when 'avatar' {
        return LDValue.of(this.avatar);
      }
      when 'country' {
        return LDValue.of(this.country);
      }
      when 'secondary' {
        return LDValue.of(this.secondary);
      }
      when else {
        if (this.custom == null) {
          return null;
        } else {
          return this.custom.get(attribute);
        }
      }
    }
  }

  private void addField(
    Map<String, Object> result,
    Boolean allAttributesPrivate,
    List<String> redacted,
    String key,
    Object value
  ) {
    if (allAttributesPrivate || (this.privateAttributeNames != null && this.privateAttributeNames.contains(key))) {
      if (value != null) {
        redacted.add(key);
      }
    } else {
      if (value != null) {
        result.put(key, value);
      }
    }
  }

  public Object toGeneric(Boolean allAttributesPrivate) {
    List<String> redacted = new List<String>();

    Map<String, Object> result = new Map<String, Object>();

    result.put('key', this.key);

    if (this.anonymous == true) {
      result.put('anonymous', this.anonymous);
    }

    this.addField(result, allAttributesPrivate, redacted, 'ip', this.ip);
    this.addField(result, allAttributesPrivate, redacted, 'firstName', this.firstName);
    this.addField(result, allAttributesPrivate, redacted, 'lastName', this.lastName);
    this.addField(result, allAttributesPrivate, redacted, 'email', this.email);
    this.addField(result, allAttributesPrivate, redacted, 'name', this.name);
    this.addField(result, allAttributesPrivate, redacted, 'avatar', this.avatar);
    this.addField(result, allAttributesPrivate, redacted, 'country', this.country);
    this.addField(result, allAttributesPrivate, redacted, 'secondary', this.secondary);

    if (this.custom != null) {
      Map<String, Object> filtered = new Map<String, Object>();

      Map<String, Object> customMap = (Map<String, Object>) this.custom.toGeneric();

      for (String key : customMap.keySet()) {
        this.addField(filtered, allAttributesPrivate, redacted, key, customMap.get(key));
      }

      if (filtered.size() != 0) {
        result.put('custom', (Object) filtered);
      }
    }

    if (redacted.size() != 0) {
      result.put('privateAttrs', (Object) redacted);
    }

    return result;
  }

  public class Builder {
    private String key;
    private Boolean anonymous;
    private String ip;
    private String firstName;
    private String lastName;
    private String email;
    private String name;
    private String avatar;
    private String country;
    private String secondary;
    private LDValueObject custom;
    private Set<String> privateAttributeNames;

    public Builder(String key) {
      this.key = key;
      this.anonymous = false;
    }

    public Builder setKey(String key) {
      this.key = key;

      return this;
    }

    public Builder setAnonymous(Boolean anonymous) {
      if (anonymous != null) {
        this.anonymous = anonymous;
      }

      return this;
    }

    public Builder setIP(String ip) {
      this.ip = ip;

      return this;
    }

    public Builder setFirstName(String firstName) {
      this.firstName = firstName;

      return this;
    }

    public Builder setLastName(String lastName) {
      this.lastName = lastName;

      return this;
    }

    public Builder setEmail(String email) {
      this.email = email;

      return this;
    }

    public Builder setName(String name) {
      this.name = name;

      return this;
    }

    public Builder setAvatar(String avatar) {
      this.avatar = avatar;

      return this;
    }

    public Builder setCountry(String country) {
      this.country = country;

      return this;
    }

    public Builder setSecondary(String secondary) {
      this.secondary = secondary;

      return this;
    }

    public Builder setCustom(LDValueObject custom) {
      this.custom = custom;

      return this;
    }

    public Builder setPrivateAttributeNames(Set<String> privateAttributeNames) {
      this.privateAttributeNames = privateAttributeNames;

      return this;
    }

    public LDUser build() {
      return new LDUser(
        this.key,
        this.anonymous,
        this.ip,
        this.firstName,
        this.lastName,
        this.email,
        this.name,
        this.avatar,
        this.country,
        this.secondary,
        this.custom,
        this.privateAttributeNames
      );
    }
  }
}
