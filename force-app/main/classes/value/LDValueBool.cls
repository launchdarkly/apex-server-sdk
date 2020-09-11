public class LDValueBool extends LDValue {
    private final Boolean value;

    private static final LDValueBool CTRUE  = new LDValueBool(true);
    private static final LDValueBool CFALSE = new LDValueBool(false);

    public static LDValueBool fromBoolean(Boolean value) {
        return value ? CTRUE : CFALSE;
    }

    private LDValueBool(Boolean value) {
        this.value = value;
    }

    public override LDValueType getType() {
        return LDValueType.CBOOLEAN;
    }

    public override Boolean booleanValue() {
        return this.value;
    }
}
