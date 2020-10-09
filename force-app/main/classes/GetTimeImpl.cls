public class GetTimeImpl implements GetTimeInterface {
    public GetTimeImpl(){}

    public Long now() {
        return DateTime.now().getTime();
    }
}