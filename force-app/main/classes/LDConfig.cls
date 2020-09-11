public class LDConfig {
    private final String key;
    private final String pollingURL;

    private LDConfig(
        String key,
        String pollingURL
    ) {
        this.key        = key;
        this.pollingURL = pollingURL;
    }

    public String getKey() {
        return this.key;
    }

    public String getPollingURL() {
        return this.pollingURL;
    }

    public class Builder {
        private String key;
        private String pollingURL = 'https://app.launchdarkly.com';

        public Builder(String key) {
            this.key = key;
        }

        public Builder setKey(String key) {
            this.key = key;

            return this;
        }

        public Builder setPollingURL(String pollingURL) {
            this.pollingURL = pollingURL;

            return this;
        }

        public LDConfig build() {
            return new LDConfig(this.key, this.pollingURL);
        }
    }
}
