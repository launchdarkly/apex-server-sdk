public interface EventSinkInterface {
    void sinkIdentify(LDEvent.Identify event);

    void sinkCustom(LDEvent.Custom event);

    void sinkFeature(LDEvent.Feature event);

    void sinkAlias(LDEvent.Alias event);
}
