public class VersionedData {
    private Integer version;
    private String  key;
    private String  kind;
    private String  raw;

    public VersionedData(String kind, Map<String, Object> obj) {
        this.version = (Integer)obj.get('version');
        this.key     = (String)obj.get('key');
        this.kind    = kind;
        this.raw     = JSON.serialize(obj);

        System.assertNotEquals(this.version, null);
        System.assertNotEquals(this.key, NULL);
        System.assertNotEquals(this.kind, NULL);
        System.assertNotEquals(this.raw, NULL);
    }

    public String getKey() {
        return this.key;
    }

    public Integer getVersion() {
        return this.version;
    }

    public String getKind() {
        return this.kind;
    }

    public String getRaw() {
        return this.raw;
    }

    public VersionedData__c getSObject() {
        VersionedData__c model = new VersionedData__c();
        model.Key__c           = this.key;
        model.Version__c       = this.version;
        model.Raw__c           = this.raw;
        model.Kind__c          = this.kind;

        return model;
    }
}
