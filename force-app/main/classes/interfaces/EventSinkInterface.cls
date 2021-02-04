public interface EventSinkInterface {
    void sinkIdentify(Event.Identify event);

    void sinkCustom(Event.Custom event);

    void sinkFeature(Event.Feature event);

    void sinkAlias(Event.Alias event);
}
