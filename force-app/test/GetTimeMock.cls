@isTest
public class GetTimeMock implements GetTimeInterface {
    Long counter;

    public GetTimeMock(){
        this.counter = 0;
    }

    public Long now() {
        this.counter += 1;
        
        return this.counter;
    }
}