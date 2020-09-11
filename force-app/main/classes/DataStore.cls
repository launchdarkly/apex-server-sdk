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
            return new DataModel.Flag(versioned.get(0).Raw__c);
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
            return new DataModel.Segment(versioned.get(0).Raw__c);
        }
    }

    public void upsertVersionedData(VersionedData value) {
        insert value.getSObject();
    }
}
