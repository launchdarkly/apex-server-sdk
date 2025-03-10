public class TtlCache {
    class TtlCacheItem {
        private Object value;
        private Integer expiration;

        TtlCacheItem(Object value, Integer expiration) {
            this.value = value;
            this.expiration = expiration;
        }

        public Object getValue() {
            return value;
        }

        public Boolean isExpired(Integer now) {
            if (expiration == null) {
                return false;
            }

            return expiration <= now;
        }

    }
}
