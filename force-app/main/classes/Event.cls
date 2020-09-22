public class Event {
    public class Identify {
        private final LDUser user;

        public Identify(LDUser user) {
            System.assertNotEquals(user, null);

            this.user = user;
        }

        public Object toGeneric() {
            Map<String, Object> event = new Map<String, Object>();

            event.put('kind', 'identify');
            event.put('key', this.user.getKey());
            event.put('user', this.user.toGeneric());

            return (Object)event;
        }
    }
}
