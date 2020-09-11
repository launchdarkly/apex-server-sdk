public abstract class LDValue {
    public abstract LDValueType getType();

    public static LDValue of(Boolean value) {
        return LDValueBool.fromBoolean(value);
    }

    public static LDValue of(Double value) {
        return LDValueNumber.fromDouble(value);
    }

    public static LDValue of(String value) {
        return LDValueString.fromString(value);
    }

    public static LDValue ofGeneric(Object value) {
        if (value == null) {
            return null;
        } else if (value instanceof Boolean) {
            return LDValueBool.fromBoolean((Boolean)value);
        } else if (value instanceof String) {
            return LDValueString.fromString((String)value);
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

    public virtual String stringValue() {
        return '';
    }

    public virtual Integer size() {
        return 0;
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
}
