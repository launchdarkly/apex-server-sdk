package main

import (
	"bytes"
	"io/ioutil"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// The event push to LaunchDarkly gets two attempts one delay apart, matching the event
// sender in LaunchDarkly's other server SDKs. These tests drive eventLoop itself rather
// than the push in isolation, because the retry has to hold alongside everything the
// loop does around it: the drain that produced the batch, the hard stop on a rejected
// SDK key, and a shutdown that arrives while the delay is running.
//
// None of this makes delivery durable. Salesforce deletes the events as it hands them
// over, so a batch that fails both attempts is lost. What these tests pin down is how
// many attempts a batch gets and what each attempt sends.

// eventLoopReturnLimit bounds how long a test waits for eventLoop to return after the
// stand-in servers stop feeding it. A loop that ignores its cancelled context hangs the
// whole test binary, so every run of it is bounded.
const eventLoopReturnLimit = 10 * time.Second

// abortEventPush is an eventPushServer status meaning "close the connection without
// answering". It produces the one failure no status code can express: client.Do returns
// an error rather than a response, the way it does when a connection drops in flight.
const abortEventPush = 0

// unauthorizedPushError is the error eventLoop returns when LaunchDarkly rejects the SDK
// key. Returning it stops the daemon, so the message is part of the behavior under test.
const unauthorizedPushError = "Pushing events to LaunchDarkly unauthorized"

// eventBatch is a drain payload holding two events. Any payload other than the empty
// array drives eventLoop into the push, and two events make a truncated retry body
// visible as something other than a length of zero.
var eventBatch = []byte(`[{"kind":"identify","key":"user-one"},{"kind":"identify","key":"user-two"}]`)

// newEventPushBridge builds a bridge whose event loop spends no real time waiting: a
// millisecond between drains and a millisecond between push attempts. The retry delay
// is a field for exactly this reason, since a real one second delay per test would add
// seconds to the suite and prove nothing extra.
func newEventPushBridge(t *testing.T, eventsURI string) *Bridge {
	t.Helper()

	bridge := newTestBridge(t, "http://unused.invalid", eventsURI)
	// Pre-seed an oauth token so requestWithOauth does not try to re-auth.
	bridge.oauthCurrentToken = "test-token"
	bridge.eventPollInterval = time.Millisecond
	bridge.eventPushRetryDelay = time.Millisecond

	return bridge
}

// salesforceOneBatch points the bridge at a Salesforce stand-in that hands over one
// batch of events and then reports an empty queue.
//
// The first drain returns the batch, which is what drives eventLoop into the push. Every
// later drain cancels the bridge and returns an empty array, so the loop stops after a
// single push cycle without pushing again. That makes the number of push attempts an
// exact expectation rather than a lower bound.
func salesforceOneBatch(t *testing.T, bridge *Bridge, payload []byte) {
	t.Helper()

	var mu sync.Mutex
	drains := 0

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		drains++
		first := drains == 1
		mu.Unlock()

		if first {
			_, _ = w.Write(payload)
			return
		}

		bridge.cancel()
		_, _ = w.Write([]byte("[]"))
	}))
	t.Cleanup(server.Close)

	bridge.salesforceURL = server.URL + "/"
}

// eventPushServer starts a LaunchDarkly stand-in for the event push endpoint. It answers
// the nth attempt with the nth entry of statuses and records the body that attempt sent,
// so a test can compare a retry against the attempt before it.
//
// An attempt past the end of statuses is recorded like any other and answered with a
// 500. A test that expects one attempt therefore reports a second one as a count, rather
// than blocking on a handler with nothing left to say.
func eventPushServer(t *testing.T, statuses ...int) (string, func() [][]byte) {
	t.Helper()

	var mu sync.Mutex
	var bodies [][]byte

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// A read that stops short shows up as a body mismatch in the test that
		// compares bodies, so the error needs no separate report here.
		body, _ := ioutil.ReadAll(r.Body)

		mu.Lock()
		attempt := len(bodies)
		bodies = append(bodies, body)
		mu.Unlock()

		status := http.StatusInternalServerError
		if attempt < len(statuses) {
			status = statuses[attempt]
		}

		// The server recovers this panic silently and closes the connection.
		if status == abortEventPush {
			panic(http.ErrAbortHandler)
		}

		w.WriteHeader(status)
	}))
	t.Cleanup(server.Close)

	return server.URL, func() [][]byte {
		mu.Lock()
		defer mu.Unlock()
		return bodies
	}
}

// runEventLoop runs eventLoop to completion and reports how long it took to return.
func runEventLoop(t *testing.T, bridge *Bridge, limit time.Duration) (time.Duration, error) {
	t.Helper()

	done := make(chan error, 1)
	started := time.Now()
	go func() { done <- bridge.eventLoop() }()

	select {
	case err := <-done:
		return time.Since(started), err
	case <-time.After(limit):
		t.Fatalf("eventLoop did not return within %s; it is still waiting on something", limit)
		return 0, nil
	}
}

// TestEventPushRetriesRecoverableFailures covers which failures earn the second attempt
// and which do not. The classification is isHTTPErrorRecoverable's, so the bridge gives
// up on the same statuses the other LaunchDarkly server SDKs give up on.
func TestEventPushRetriesRecoverableFailures(t *testing.T) {
	tests := []struct {
		name         string
		statuses     []int
		wantAttempts int
		wantGaveUp   bool
	}{
		{
			name:         "a dropped connection is retried",
			statuses:     []int{abortEventPush, http.StatusAccepted},
			wantAttempts: 2,
		},
		{
			name:         "429 is retried",
			statuses:     []int{http.StatusTooManyRequests, http.StatusAccepted},
			wantAttempts: 2,
		},
		{
			name:         "503 is retried",
			statuses:     []int{http.StatusServiceUnavailable, http.StatusAccepted},
			wantAttempts: 2,
		},
		{
			name:         "408 is retried",
			statuses:     []int{http.StatusRequestTimeout, http.StatusAccepted},
			wantAttempts: 2,
		},
		{
			name:         "400 is retried",
			statuses:     []int{http.StatusBadRequest, http.StatusAccepted},
			wantAttempts: 2,
		},
		// Two attempts is the whole budget. A third would need a third status, and the
		// stand-in answers one that is recoverable as well, so a loop that kept going
		// would keep going forever.
		{
			name:         "the retry is the final attempt",
			statuses:     []int{http.StatusServiceUnavailable, http.StatusServiceUnavailable},
			wantAttempts: 2,
			wantGaveUp:   true,
		},
		{
			name:         "404 is not retried",
			statuses:     []int{http.StatusNotFound},
			wantAttempts: 1,
			wantGaveUp:   true,
		},
		{
			name:         "405 is not retried",
			statuses:     []int{http.StatusMethodNotAllowed},
			wantAttempts: 1,
			wantGaveUp:   true,
		},
		{
			name:         "200 needs no retry",
			statuses:     []int{http.StatusOK},
			wantAttempts: 1,
		},
		{
			name:         "202 needs no retry",
			statuses:     []int{http.StatusAccepted},
			wantAttempts: 1,
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			logged := captureLog(t)
			pushURI, attempts := eventPushServer(t, test.statuses...)

			bridge := newEventPushBridge(t, pushURI)
			salesforceOneBatch(t, bridge, eventBatch)

			_, err := runEventLoop(t, bridge, eventLoopReturnLimit)
			if err != nil {
				t.Fatalf("eventLoop returned unexpected error: %v", err)
			}

			if got := len(attempts()); got != test.wantAttempts {
				t.Errorf("the push was attempted %d times, want %d\nlog:\n%s",
					got, test.wantAttempts, logged.String())
			}

			// A lost batch is logged plainly, because nothing sends it again: the
			// events are already deleted from Salesforce.
			gaveUp := strings.Contains(logged.String(), "this batch is lost")
			if gaveUp != test.wantGaveUp {
				t.Errorf("reported a lost batch = %v, want %v\nlog:\n%s",
					gaveUp, test.wantGaveUp, logged.String())
			}
		})
	}
}

// TestEventPushRetriesTheWholeBatch is the regression test for a retry that posts an
// empty body. client.Do reads the request body to the end, so a retry that reuses the
// first attempt's request sends nothing at all -- and the events it was carrying are
// gone from Salesforce either way. The push has to build a fresh request per attempt.
//
// Comparing the two bodies byte for byte is the point. A retry that carried a truncated
// batch would still be non-empty.
func TestEventPushRetriesTheWholeBatch(t *testing.T) {
	pushURI, attempts := eventPushServer(t, http.StatusServiceUnavailable, http.StatusAccepted)

	bridge := newEventPushBridge(t, pushURI)
	salesforceOneBatch(t, bridge, eventBatch)

	if _, err := runEventLoop(t, bridge, eventLoopReturnLimit); err != nil {
		t.Fatalf("eventLoop returned unexpected error: %v", err)
	}

	bodies := attempts()
	if len(bodies) != 2 {
		t.Fatalf("the push was attempted %d times, want 2", len(bodies))
	}

	if !bytes.Equal(bodies[0], eventBatch) {
		t.Errorf("the first attempt sent %d bytes (%q), want the drained batch (%q)",
			len(bodies[0]), bodies[0], eventBatch)
	}
	if !bytes.Equal(bodies[1], bodies[0]) {
		t.Errorf("the retry sent %d bytes (%q), want the same bytes as the first attempt (%q)",
			len(bodies[1]), bodies[1], bodies[0])
	}
}

// TestEventPushStopsTheDaemonWhenUnauthorized covers the statuses that end the process.
// A rejected SDK key does not become acceptable on a retry, and the same key authorizes
// every other LaunchDarkly request the daemon makes, so neither status may spend an
// attempt and neither may be survived.
func TestEventPushStopsTheDaemonWhenUnauthorized(t *testing.T) {
	tests := []struct {
		name   string
		status int
	}{
		{name: "401 unauthorized", status: http.StatusUnauthorized},
		{name: "403 forbidden", status: http.StatusForbidden},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			// A second status the stand-in would answer with, so a bridge that retried
			// this would be visible as an attempt count rather than an error.
			pushURI, attempts := eventPushServer(t, test.status, http.StatusAccepted)

			bridge := newEventPushBridge(t, pushURI)
			salesforceOneBatch(t, bridge, eventBatch)

			_, err := runEventLoop(t, bridge, eventLoopReturnLimit)
			if err == nil {
				t.Fatalf("eventLoop returned no error, want %q so the daemon stops", unauthorizedPushError)
			}
			if err.Error() != unauthorizedPushError {
				t.Errorf("eventLoop returned %q, want %q", err.Error(), unauthorizedPushError)
			}

			if got := len(attempts()); got != 1 {
				t.Errorf("the push was attempted %d times, want 1: a retry on %d is a wasted attempt",
					got, test.status)
			}
		})
	}
}

// TestEventPushShutdownEndsTheRetryDelay covers a shutdown that arrives while the delay
// is running. A bare sleep would hold the daemon open for the rest of the delay, which
// is what makes Ctrl-C feel like a hang, so the delay waits on the context as well.
//
// The delay here is long enough that waiting it out cannot be mistaken for anything
// else, and the drain interval is long as well so the retry delay is the only wait the
// loop can be sitting in when the context is cancelled.
func TestEventPushShutdownEndsTheRetryDelay(t *testing.T) {
	const retryDelay = 30 * time.Second
	// Generous on a loaded machine, and far below the delay the loop must not wait out.
	const returnLimit = 3 * time.Second

	var mu sync.Mutex
	pushes := 0

	logged := captureLog(t)
	bridge := newEventPushBridge(t, "http://unused.invalid")
	bridge.eventPushRetryDelay = retryDelay
	bridge.eventPollInterval = time.Minute

	ldServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		pushes++
		mu.Unlock()

		// Cancelling before answering means the context is already done by the time
		// the loop reaches the delay. A recoverable status is what sends it there.
		bridge.cancel()
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer ldServer.Close()
	bridge.launchDarklyEventsURI = ldServer.URL

	salesforceOneBatch(t, bridge, eventBatch)

	elapsed, err := runEventLoop(t, bridge, returnLimit)
	if err != nil {
		t.Fatalf("eventLoop returned unexpected error: %v", err)
	}
	t.Logf("eventLoop returned %s into a %s retry delay", elapsed, retryDelay)

	// The retry was entered and then abandoned, rather than never being reached.
	if !strings.Contains(logged.String(), "retrying the event push") {
		t.Errorf("eventLoop never reached the retry delay\nlog:\n%s", logged.String())
	}

	mu.Lock()
	defer mu.Unlock()
	if pushes != 1 {
		t.Errorf("the push was attempted %d times, want 1: shutdown abandons the retry", pushes)
	}
}

// TestIsHTTPErrorRecoverable pins the classification against go-sdk-events, which is
// where these exact statuses come from. The bridge handles 401 and 403 before it
// classifies anything, so their entries here record what the function says rather than
// what the push does with them.
func TestIsHTTPErrorRecoverable(t *testing.T) {
	tests := []struct {
		status int
		want   bool
	}{
		{status: http.StatusOK, want: true},
		{status: http.StatusAccepted, want: true},
		{status: http.StatusMovedPermanently, want: true},
		{status: http.StatusBadRequest, want: true},
		{status: http.StatusUnauthorized, want: false},
		{status: http.StatusForbidden, want: false},
		{status: http.StatusNotFound, want: false},
		{status: http.StatusMethodNotAllowed, want: false},
		{status: http.StatusRequestTimeout, want: true},
		{status: http.StatusConflict, want: false},
		{status: http.StatusRequestEntityTooLarge, want: false},
		{status: http.StatusTooManyRequests, want: true},
		{status: 499, want: false},
		{status: http.StatusInternalServerError, want: true},
		{status: http.StatusBadGateway, want: true},
		{status: http.StatusServiceUnavailable, want: true},
		{status: http.StatusGatewayTimeout, want: true},
		// A status the service has never returned costs a retry rather than a batch.
		{status: 599, want: true},
	}

	for _, test := range tests {
		if got := isHTTPErrorRecoverable(test.status); got != test.want {
			t.Errorf("isHTTPErrorRecoverable(%d) = %v, want %v", test.status, got, test.want)
		}
	}
}

// TestPushDisposition pins the three outcomes a failed push attempt can report. A log
// line that does not distinguish a first failure from a final one leaves an operator
// unable to tell a transient blip from lost data, which is the whole reason the
// annotation exists.
//
// The "this batch is lost" substring is load-bearing beyond the wording:
// TestEventPushRetriesRecoverableFailures decides wantGaveUp by searching for it, so
// both give-up outcomes must carry it and the retry outcome must not.
func TestPushDisposition(t *testing.T) {
	tests := []struct {
		name        string
		attempt     int
		recoverable bool
		want        string
	}{
		{
			name:        "a recoverable failure with an attempt left retries",
			attempt:     0,
			recoverable: true,
			want:        "will retry",
		},
		{
			name:        "a recoverable failure on the last attempt gives up",
			attempt:     EVENT_PUSH_ATTEMPTS - 1,
			recoverable: true,
			want:        "out of attempts, this batch is lost",
		},
		{
			// The status decides this one, not the budget, so it reads the same on
			// either attempt. Spending the second attempt would resend identical
			// bytes to the same endpoint.
			name:        "an unrecoverable failure gives up with an attempt left",
			attempt:     0,
			recoverable: false,
			want:        "not retryable, this batch is lost",
		},
		{
			name:        "an unrecoverable failure gives up on the last attempt",
			attempt:     EVENT_PUSH_ATTEMPTS - 1,
			recoverable: false,
			want:        "not retryable, this batch is lost",
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			got := pushDisposition(test.attempt, test.recoverable)
			if got != test.want {
				t.Errorf("pushDisposition(%d, %v) = %q, want %q",
					test.attempt, test.recoverable, got, test.want)
			}

			lost := strings.Contains(got, "this batch is lost")
			if wantLost := test.want != "will retry"; lost != wantLost {
				t.Errorf("pushDisposition(%d, %v) = %q, reports a lost batch = %v, want %v",
					test.attempt, test.recoverable, got, lost, wantLost)
			}
		})
	}
}

// TestEventPushAnnotatesTheFirstFailure drives the annotation through eventLoop rather
// than calling pushDisposition directly, so it also proves the loop passes the live
// attempt index. A 503 then a 200 means the first failure has a retry behind it, so the
// log has to say so and must not claim the batch was lost -- it was delivered.
func TestEventPushAnnotatesTheFirstFailure(t *testing.T) {
	logged := captureLog(t)

	pushURI, attempts := eventPushServer(t, http.StatusServiceUnavailable, http.StatusOK)

	bridge := newEventPushBridge(t, pushURI)
	salesforceOneBatch(t, bridge, eventBatch)

	if _, err := runEventLoop(t, bridge, eventLoopReturnLimit); err != nil {
		t.Fatalf("eventLoop returned unexpected error: %v", err)
	}

	if got := len(attempts()); got != 2 {
		t.Fatalf("the push was attempted %d times, want 2\nlog:\n%s", got, logged.String())
	}

	if !strings.Contains(logged.String(), "will retry") {
		t.Errorf("the first failure did not report that a retry follows\nlog:\n%s", logged.String())
	}

	if strings.Contains(logged.String(), "this batch is lost") {
		t.Errorf("a delivered batch was reported as lost\nlog:\n%s", logged.String())
	}
}
