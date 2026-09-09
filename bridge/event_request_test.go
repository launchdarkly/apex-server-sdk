package main

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
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
	// because eventLoop builds its poll URI directly from salesforceURL.
	const badSalesforceURL = "http://salesforce.invalid/\x7f/"

	bridge := newTestBridge(t, "http://unused.invalid", "http://unused.invalid")
	bridge.salesforceURL = badSalesforceURL

	// Confirm the fixture still reaches the failure under test, and capture the error
	// to compare against without depending on how url.Parse words it. The URI has to
	// match the one eventLoop builds, drain limit included, because url.Parse quotes
	// the whole URI back in its message.
	_, wantErr := http.NewRequest("GET", fmt.Sprintf("%sevent?%s=%d",
		badSalesforceURL, MAX_EVENTS_PARAM, bridge.maxEventsPerDrain), nil)
	if wantErr == nil {
		t.Fatalf("http.NewRequest accepted %q, so this test no longer exercises a construction failure", badSalesforceURL)
	}

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

// TestEventPollCarriesTheDrainLimit covers the parameter that keeps a drain under the
// governor limits. Without it the org reads and deletes every queued row, and once the
// table passes a limit the query throws before the delete runs -- so nothing is removed
// and no later drain can shrink the table either.
func TestEventPollCarriesTheDrainLimit(t *testing.T) {
	var captured string
	var polled bool
	var cancel context.CancelFunc

	sfServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		captured = r.URL.Query().Get(MAX_EVENTS_PARAM)
		polled = true
		cancel()
		// An empty bundle, so the cycle ends without a push to LaunchDarkly.
		_, _ = w.Write([]byte("[]"))
	}))
	defer sfServer.Close()

	bridge := newTestBridge(t, "http://unused.invalid", "http://unused.invalid")
	bridge.salesforceURL = sfServer.URL + "/"
	bridge.maxEventsPerDrain = 250
	cancel = bridge.cancel
	// Pre-seed an oauth token so requestWithOauth does not try to re-auth.
	bridge.oauthCurrentToken = "test-token"

	if err := bridge.eventLoop(); err != nil {
		t.Fatalf("eventLoop returned unexpected error: %v", err)
	}
	if !polled {
		t.Fatal("eventLoop did not poll Salesforce for events")
	}
	if want := strconv.Itoa(bridge.maxEventsPerDrain); captured != want {
		t.Errorf("poll request %s = %q, want %q", MAX_EVENTS_PARAM, captured, want)
	}
}

// TestResolveMaxEventsPerDrain covers the range MAX_EVENTS_PER_DRAIN is held to.
//
// The ceiling is the point: a drain deletes exactly the rows it read, and one Apex
// transaction can delete 10,000 of them. The org lowers an over-large request too, but
// checking it here names the value at startup instead of silently sending it.
func TestResolveMaxEventsPerDrain(t *testing.T) {
	tests := []struct {
		name  string
		env   string
		unset bool
		want  int
	}{
		{name: "unset uses the default", unset: true, want: MAX_EVENTS_PER_DRAIN},
		{name: "blank uses the default", env: "", want: MAX_EVENTS_PER_DRAIN},
		{name: "a value in range is honored", env: "250", want: 250},
		{name: "the ceiling itself is honored", env: strconv.Itoa(MAX_EVENTS_PER_DRAIN), want: MAX_EVENTS_PER_DRAIN},
		{name: "above the ceiling is lowered", env: "50000", want: MAX_EVENTS_PER_DRAIN},
		{name: "zero uses the default", env: "0", want: MAX_EVENTS_PER_DRAIN},
		{name: "negative uses the default", env: "-1", want: MAX_EVENTS_PER_DRAIN},
		{name: "unparseable uses the default", env: "many", want: MAX_EVENTS_PER_DRAIN},
		{name: "a float uses the default", env: "250.5", want: MAX_EVENTS_PER_DRAIN},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			// Unset and blank are different cases: both resolve to the default, but
			// only unset stands for a bridge that was never configured.
			if test.unset {
				unsetEnv(t, "MAX_EVENTS_PER_DRAIN")
			} else {
				setEnv(t, "MAX_EVENTS_PER_DRAIN", test.env)
			}

			if got := resolveMaxEventsPerDrain(); got != test.want {
				t.Errorf("resolveMaxEventsPerDrain() = %d, want %d", got, test.want)
			}
		})
	}
}
