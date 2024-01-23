public abstract class LDValue {
  public abstract LDValueType getType();

  public static LDValue of(Boolean value) {
    return LDValueBool.fromBoolean(value);
  }

  public static LDValue of(Integer value) {
    return LDValueNumber.fromInteger(value);
  }

  public static LDValue of(Double value) {
    return LDValueNumber.fromDouble(value);
  }

  public static LDValue of(Decimal value) {
    return LDValueNumber.fromDecimal(value);
  }

  public static LDValue of(String value) {
    return LDValueString.fromString(value);
  }

  public static LDValue ofGeneric(Object value) {
    if (value == null) {
      return null;
    } else if (value instanceof Boolean) {
      return LDValueBool.fromBoolean((Boolean) value);
    } else if (value instanceof Integer) {
      return LDValueNumber.fromInteger((Integer) value);
    } else if (value instanceof Double) {
      return LDValueNumber.fromDouble((Double) value);
    } else if (value instanceof Decimal) {
      return LDValueNumber.fromDecimal((Decimal) value);
    } else if (value instanceof String) {
      return LDValueString.fromString((String) value);
    } else if (value instanceof List<Object>) {
      List<Object> valueConcrete = (List<Object>) value;

      LDValueArray.Builder builder = new LDValueArray.Builder();

      for (Object item : valueConcrete) {
        if (item != null) {
          builder.add(ofGeneric(item));
        }
      }

      return builder.build();
    } else if (value instanceof Map<String, Object>) {
      Map<String, Object> valueConcrete = (Map<String, Object>) value;

      LDValueObject.Builder builder = new LDValueObject.Builder();

      for (String key : valueConcrete.keySet()) {
        Object item = valueConcrete.get(key);

        if (item != null) {
          builder.set(key, ofGeneric(item));
        }
      }

      return builder.build();
    }

    return null;
  }

  public virtual Boolean booleanValue() {
    return false;
  }

  public virtual Double doubleValue() {
    return 0;
  }

  public virtual Integer intValue() {
    return 0;
  }

  public virtual Long longValue() {
    return 0;
  }

  public virtual String stringValue() {
    return '';
  }

  public virtual Integer size() {
    return 0;
  }

  public virtual Object toGeneric() {
    return null;
  }

  public virtual LDValue get(Integer index) {
    return null;
  }

  public virtual LDValue get(String index) {
    return null;
  }

  public virtual Boolean isInt() {
    return false;
  }

  public virtual Boolean isNumber() {
    return false;
  }

  public virtual Boolean isString() {
    return false;
  }

  public Boolean equals(LDValue other) {
    if (this.getType() == other.getType()) {
      return this.toGeneric() == other.toGeneric();
    } else {
      return false;
    }
  }
}
