public class DataSource implements DataSourceInterface {
    private final LDConfig           config;
    private final DataStoreInterface store;

    public DataSource(final LDConfig config, final DataStoreInterface store) {
        this.config = config;
        this.store  = store;
    }

    public void poll() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(this.config.getPollingURL() + '/sdk/latest-all');
        req.setMethod('GET');
        req.setHeader('Authorization', this.config.getKey());

        Http http = new Http();
        HTTPResponse res = http.send(req);
        System.debug(res.getBody());

        Map<String, Object> kinds =
            (Map<String, Object>)JSON.deserializeUntyped(res.getBody());

        for (String kind : kinds.keySet()) {
            Map<String, Object> flags = (Map<String, Object>)kinds.get(kind);

            for (String key : flags.keySet()) {
                Map<String, Object> flag = (Map<String, Object>)flags.get(key);

                VersionedData versioned = new VersionedData(kind, flag);

                this.store.upsertVersionedData(versioned);
            }
        }
    }
}
