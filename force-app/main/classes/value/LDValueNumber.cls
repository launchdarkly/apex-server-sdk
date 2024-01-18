public class LDValueNumber extends LDValue {
  private final Double value;

  public static LDValueNumber fromDouble(Double value) {
    if (value == null) {
      return null;
    } else {
      return new LDValueNumber(value);
    }
  }

  public static LDValueNumber fromDecimal(Decimal value) {
    if (value == null) {
      return null;
    } else {
      return new LDValueNumber((Double) value);
    }
  }

  public static LDValueNumber fromInteger(Integer value) {
    if (value == null) {
      return null;
    } else {
      return new LDValueNumber((Double) value);
    }
  }

  private LDValueNumber(Double value) {
    this.value = value;
  }

  public override LDValueType getType() {
    return LDValueType.CNUMBER;
  }

  public override Double doubleValue() {
    return this.value;
  }

  public override Integer intValue() {
    return this.value.intValue();
  }

  public override Long longValue() {
    return this.value.longValue();
  }

  public override Boolean isInt() {
    return this.value == (Double) ((Integer) this.value);
  }

  public override Boolean isNumber() {
    return true;
  }

  public override Object toGeneric() {
    return (Object) this.value;
  }
}
