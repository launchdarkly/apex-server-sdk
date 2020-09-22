public class DataStore implements DataStoreInterface {
    public DataStore() {

    }

    public DataModel.Flag getFlag(String key) {
        List<VersionedData__c> versioned = [
            SELECT
                Version__c,
                Raw__c,
                Key__c,
                Kind__c
            FROM
                VersionedData__c
            WHERE
                    (Key__c  = :key)
                AND (Kind__c = 'flags')
            LIMIT 1
        ];

        if (versioned.isEmpty()) {
            return null;
        } else {
            try {
                return new DataModel.Flag(versioned.get(0).Raw__c);
            } catch (Exception err) {
                return null;
            }
        }
    }

    public DataModel.Segment getSegment(String key) {
        List<VersionedData__c> versioned = [
            SELECT
                Version__c,
                Raw__c,
                Key__c,
                Kind__c
            FROM
                VersionedData__c
            WHERE
                    (Key__c  = :key)
                AND (Kind__c = 'segments')
            LIMIT 1
        ];

        if (versioned.isEmpty()) {
            return null;
        } else {
            try {
                return new DataModel.Segment(versioned.get(0).Raw__c);
            } catch (Exception err) {
                return null;
            }
        }
    }

    public Map<String, DataModel.Flag> allFlags() {
        Map<String, DataModel.Flag> result = new Map<String, DataModel.Flag>();

        List<VersionedData__c> flags = [
            SELECT
                Version__c,
                Raw__c,
                Key__c,
                Kind__c
            FROM
                VersionedData__c
            WHERE
                Kind__c = 'flags'
        ];

        for (VersionedData__C flag : flags) {
            try {
                result.put(flag.Key__c, new DataModel.Flag(flag.Raw__c));
            } catch (Exception err) {
                // required by compiler
            }
        }

        return result;
    }

    public void putAll(Map<String, Object> kinds) {
        // delete existing store values
        List<VersionedData__c> existingFeatures = [select Key__c from VersionedData__C];
        delete existingFeatures;
        // iterate over kinds of features such as flags / segments
        for (String kind : kinds.keySet()) {
            Map<String, Object> features = (Map<String, Object>)kinds.get(kind);

            for (String key : features.keySet()) {
                Map<String, Object> feature = (Map<String, Object>)features.get(key);

                VersionedData versioned = new VersionedData(kind, feature);

                this.insertVersionedData(versioned);
            }
        }
    }

    public void insertVersionedData(VersionedData value) {
        insert value.getSObject();
    }
}
