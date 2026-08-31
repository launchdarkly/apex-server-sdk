package main

import (
	"net/http"
	"testing"
	"time"
)

// TestEventLoopReturnsAPollRequestError covers what eventLoop does when it cannot
// build its poll request at all. pollURI comes from SALESFORCE_URL, so a value
// url.Parse rejects makes http.NewRequest hand back a nil request. Setting a header
// on that request panics the daemon, so the loop has to check the error first. It
// returns rather than logging and polling again because pollURI is fixed for the life
// of the loop: every later attempt fails the same way, so there is nothing to retry.
// This matches featureLoop, whose identical call already returns.
func TestEventLoopReturnsAPollRequestError(t *testing.T) {
	// A control character is what url.Parse refuses. The trailing slash is there
	// because eventLoop appends "event" directly to salesforceURL.
	const badSalesforceURL = "http://salesforce.invalid/\x7f/"

	// Confirm the fixture still reaches the failure under test, and capture the error
	// to compare against without depending on how url.Parse words it.
	_, wantErr := http.NewRequest("GET", badSalesforceURL+"event", nil)
	if wantErr == nil {
		t.Fatalf("http.NewRequest accepted %q, so this test no longer exercises a construction failure", badSalesforceURL)
	}

	bridge := newTestBridge(t, "http://unused.invalid", "http://unused.invalid")
	bridge.salesforceURL = badSalesforceURL

	type outcome struct {
		err       error
		recovered interface{}
	}

	// eventLoop runs in its own goroutine so that a panic can be recovered here
	// instead of taking the whole test binary down, and so that a loop that neither
	// returns nor panics is reported as a timeout rather than hanging the run.
	done := make(chan outcome, 1)
	go func() {
		var got outcome
		defer func() {
			got.recovered = recover()
			done <- got
		}()
		got.err = bridge.eventLoop()
	}()

	select {
	case got := <-done:
		if got.recovered != nil {
			t.Fatalf("eventLoop panicked instead of returning the poll request error: %v", got.recovered)
		}
		if got.err == nil {
			t.Fatal("eventLoop returned nil, want the error from constructing the poll request")
		}
		if got.err.Error() != wantErr.Error() {
			t.Errorf("eventLoop returned %q, want the construction error %q", got.err, wantErr)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("eventLoop kept polling instead of returning the poll request error")
	}
}
