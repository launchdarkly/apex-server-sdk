public interface DataStoreInterface {
  DataModel.Flag getFlag(String key);

  DataModel.Segment getSegment(String key);

  Map<String, DataModel.Flag> allFlags();
}
