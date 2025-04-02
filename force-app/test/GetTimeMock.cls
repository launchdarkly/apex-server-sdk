@isTest
public class GetTimeMock implements GetTimeInterface {
  public Long counter;

  public GetTimeMock() {
    this.counter = 0;
  }

  public Long now() {
    this.counter += 1;

    return this.counter;
  }
}
