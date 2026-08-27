public class LDValueString extends LDValue {
  private final String value;

  public static LDValueString fromString(String value) {
    if (value == null) {
      return null;
    } else {
      return new LDValueString(value);
    }
  }

  private LDValueString(String value) {
    this.value = value;
  }

  public override LDValueType getType() {
    return LDValueType.CSTRING;
  }

  public override String stringValue() {
    return this.value;
  }

  public override Object toGeneric() {
    return (Object) this.value;
  }

  public override Boolean isString() {
    return true;
  }

  // The Apex == operator ignores letter case for Strings. String.equals compares
  // the exact characters. LaunchDarkly compares string values with case sensitivity.
  public override Boolean equals(LDValue other) {
    return other.getType() == LDValueType.CSTRING && this.value.equals(other.stringValue());
  }
}
