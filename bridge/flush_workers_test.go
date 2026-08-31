package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// The event push runs on its own goroutine, bounded at MAX_EVENT_FLUSH_WORKERS, so a slow
// LaunchDarkly endpoint no longer holds up the next drain. These tests cover the bound and
// the thing the bound exists for.
//
// The property that matters most is not the parallelism, it is what happens when every
// slot is taken. EventREST.prepareEvents deletes the rows as it hands them over, so a
// batch drained with nowhere to send it is a batch lost. The bridge therefore declines to
// drain at all, which leaves the events in the org -- the same choice the other
// LaunchDarkly SDKs make by keeping events in their outbox when every flush worker is
// busy. TestDrainIsSkippedWhenEveryFlushSlotIsBusy is that assertion.

// blockingPushServer answers event pushes only once released, and reports how many pushes
// have arrived. It is how a test holds flush slots open.
func blockingPushServer(t *testing.T) (uri string, arrived func() int, release func()) {
	t.Helper()

	var mu sync.Mutex
	count := 0
	gate := make(chan struct{})

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		count++
		mu.Unlock()

		<-gate
		w.WriteHeader(http.StatusAccepted)
	}))
	t.Cleanup(server.Close)

	var once sync.Once

	return server.URL, func() int {
			mu.Lock()
			defer mu.Unlock()
			return count
		}, func() {
			once.Do(func() { close(gate) })
		}
}

// countingSalesforce hands over a batch on every drain and counts the drains, so a test
// can assert a drain did not happen. It never cancels the bridge; the test does that.
func countingSalesforce(t *testing.T, bridge *Bridge, payload []byte) func() int {
	t.Helper()

	var mu sync.Mutex
	drains := 0

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		drains++
		mu.Unlock()

		_, _ = w.Write(payload)
	}))
	t.Cleanup(server.Close)

	bridge.salesforceURL = server.URL + "/"

	return func() int {
		mu.Lock()
		defer mu.Unlock()
		return drains
	}
}

// TestDrainIsSkippedWhenEveryFlushSlotIsBusy is the regression test for losing a batch to
// backpressure.
//
// Every slot is held by a push that will not answer. The bridge must stop draining rather
// than drain into a full pool, because the rows are deleted by the drain itself. Asserting
// on the *drain* count rather than the push count is the whole point: a bridge that
// drained and then dropped the batch would look identical from the push side.
func TestDrainIsSkippedWhenEveryFlushSlotIsBusy(t *testing.T) {
	logged := captureLog(t)

	pushURI, pushesArrived, release := blockingPushServer(t)
	defer release()

	bridge := newEventPushBridge(t, pushURI)
	bridge.eventPollInterval = 5 * time.Millisecond
	drains := countingSalesforce(t, bridge, eventBatch)

	done := make(chan error, 1)
	go func() { done <- bridge.eventLoop() }()

	// Wait until every slot is occupied by a blocked push.
	deadline := time.After(5 * time.Second)
	for pushesArrived() < MAX_EVENT_FLUSH_WORKERS {
		select {
		case <-deadline:
			t.Fatalf("only %d of %d pushes started\nlog:\n%s",
				pushesArrived(), MAX_EVENT_FLUSH_WORKERS, logged.String())
		case <-time.After(time.Millisecond):
		}
	}

	// With no slot free, further cycles must not drain. Give the loop several intervals
	// to prove it is choosing not to, rather than merely being slow.
	settled := drains()
	time.Sleep(20 * bridge.eventPollInterval)

	if grew := drains() - settled; grew != 0 {
		t.Errorf("the bridge drained %d more times with every flush slot busy; those "+
			"events were deleted from Salesforce with nowhere to send them\nlog:\n%s",
			grew, logged.String())
	}

	if drains() != MAX_EVENT_FLUSH_WORKERS {
		t.Errorf("drained %d times, want %d -- one per slot and no more",
			drains(), MAX_EVENT_FLUSH_WORKERS)
	}

	if !strings.Contains(logged.String(), "are busy, leaving") {
		t.Errorf("the bridge did not report declining to drain\nlog:\n%s", logged.String())
	}

	release()
	bridge.cancel()
	if err := <-done; err != nil {
		t.Fatalf("eventLoop returned unexpected error: %v", err)
	}
}

// TestFlushSlotsAreReleasedOnEveryOutcome drives more batches through the bridge than
// there are slots, so a slot leaked on any push outcome shows up as the loop going quiet.
// A leak is invisible with fewer batches than slots, which is why the count is higher.
func TestFlushSlotsAreReleasedOnEveryOutcome(t *testing.T) {
	tests := []struct {
		name   string
		status int
	}{
		{name: "success", status: http.StatusAccepted},
		{name: "exhausted retries", status: http.StatusServiceUnavailable},
		{name: "not retryable", status: http.StatusNotFound},
		{name: "dropped connection", status: abortEventPush},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			const batches = MAX_EVENT_FLUSH_WORKERS + 3

			logged := captureLog(t)

			var mu sync.Mutex
			pushes := 0

			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				mu.Lock()
				pushes++
				mu.Unlock()

				if test.status == abortEventPush {
					panic(http.ErrAbortHandler)
				}
				w.WriteHeader(test.status)
			}))
			defer server.Close()

			bridge := newEventPushBridge(t, server.URL)
			bridge.eventPollInterval = 2 * time.Millisecond
			drains := countingSalesforce(t, bridge, eventBatch)

			done := make(chan error, 1)
			go func() { done <- bridge.eventLoop() }()

			// Every drain needs a slot, so reaching this count at all proves slots came
			// back. A leak stalls the loop permanently and this times out instead.
			deadline := time.After(10 * time.Second)
			for drains() < batches {
				select {
				case <-deadline:
					t.Fatalf("only %d of %d drains happened, so a flush slot was not "+
						"released\nlog:\n%s", drains(), batches, logged.String())
				case <-time.After(time.Millisecond):
				}
			}

			bridge.cancel()
			if err := <-done; err != nil {
				t.Fatalf("eventLoop returned unexpected error: %v", err)
			}
		})
	}
}

// TestASlowPushDoesNotDelayTheNextDrain is the reason for the change. With the push inline
// the loop could not drain again until LaunchDarkly answered; now it drains on its own
// cadence while pushes are still outstanding.
func TestASlowPushDoesNotDelayTheNextDrain(t *testing.T) {
	logged := captureLog(t)

	pushURI, pushesArrived, release := blockingPushServer(t)
	defer release()

	bridge := newEventPushBridge(t, pushURI)
	bridge.eventPollInterval = 2 * time.Millisecond
	drains := countingSalesforce(t, bridge, eventBatch)

	done := make(chan error, 1)
	go func() { done <- bridge.eventLoop() }()

	// More than one drain while the first push is still unanswered is the property. The
	// bound means this can reach MAX_EVENT_FLUSH_WORKERS and no further.
	deadline := time.After(5 * time.Second)
	for drains() < 2 {
		select {
		case <-deadline:
			t.Fatalf("only %d drain(s) happened while a push was outstanding; the push "+
				"is still blocking the drain\nlog:\n%s", drains(), logged.String())
		case <-time.After(time.Millisecond):
		}
	}

	if pushesArrived() == 0 {
		t.Error("no push was outstanding, so this proves nothing about blocking")
	}

	release()
	bridge.cancel()
	if err := <-done; err != nil {
		t.Fatalf("eventLoop returned unexpected error: %v", err)
	}
}

// TestConcurrentBatchesGetDistinctPayloadIDs guards deduplication under parallelism. Each
// batch is its own payload, so sharing an id across two would make LaunchDarkly discard
// one of them as a duplicate of the other.
func TestConcurrentBatchesGetDistinctPayloadIDs(t *testing.T) {
	logged := captureLog(t)

	var mu sync.Mutex
	ids := map[string]int{}
	gate := make(chan struct{})

	var gateOnce sync.Once
	openGate := func() { gateOnce.Do(func() { close(gate) }) }

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		ids[r.Header.Get(PAYLOAD_ID_HEADER)]++
		seen := len(ids)
		mu.Unlock()

		// Hold every push open until all the slots are in use, so the batches really do
		// overlap rather than running one after another.
		if seen >= MAX_EVENT_FLUSH_WORKERS {
			openGate()
		}
		<-gate
		w.WriteHeader(http.StatusAccepted)
	}))
	defer server.Close()
	// Runs before server.Close, so a t.Fatal below reports instead of deadlocking there.
	defer openGate()

	bridge := newEventPushBridge(t, server.URL)
	bridge.eventPollInterval = 2 * time.Millisecond
	countingSalesforce(t, bridge, eventBatch)

	done := make(chan error, 1)
	go func() { done <- bridge.eventLoop() }()

	select {
	case <-gate:
	case <-time.After(5 * time.Second):
		mu.Lock()
		got := len(ids)
		mu.Unlock()
		t.Fatalf("only %d concurrent pushes started, want %d\nlog:\n%s",
			got, MAX_EVENT_FLUSH_WORKERS, logged.String())
	}

	bridge.cancel()
	if err := <-done; err != nil {
		t.Fatalf("eventLoop returned unexpected error: %v", err)
	}

	mu.Lock()
	defer mu.Unlock()
	if len(ids) < MAX_EVENT_FLUSH_WORKERS {
		t.Fatalf("saw %d distinct payload ids across concurrent batches, want at least %d",
			len(ids), MAX_EVENT_FLUSH_WORKERS)
	}
	for id, count := range ids {
		if id == "" {
			t.Error("a concurrent batch sent no payload id")
		}
		if count != 1 {
			t.Errorf("payload id %q was sent by %d pushes; concurrent batches must not "+
				"share one, or LaunchDarkly discards one as a duplicate", id, count)
		}
	}
}

// TestShutdownWaitsForAnInFlightPush covers the loss this change could have introduced.
// A push still running at shutdown holds events Salesforce has already deleted, so the
// loop gives it a bounded chance to finish instead of returning immediately.
func TestShutdownWaitsForAnInFlightPush(t *testing.T) {
	logged := captureLog(t)

	var mu sync.Mutex
	completed := 0
	started := make(chan struct{}, 1)
	proceed := make(chan struct{})

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case started <- struct{}{}:
		default:
		}

		<-proceed

		mu.Lock()
		completed++
		mu.Unlock()

		w.WriteHeader(http.StatusAccepted)
	}))
	defer server.Close()

	// Registered after server.Close so it runs before it. httptest.Server.Close blocks
	// until every handler returns, so a t.Fatal below would otherwise deadlock in Close
	// instead of reporting -- the test would hang out its whole timeout with no message.
	var releaseOnce sync.Once
	release := func() { releaseOnce.Do(func() { close(proceed) }) }
	defer release()

	bridge := newEventPushBridge(t, server.URL)
	bridge.eventPollInterval = time.Minute
	countingSalesforce(t, bridge, eventBatch)

	done := make(chan error, 1)
	go func() { done <- bridge.eventLoop() }()

	select {
	case <-started:
	case <-time.After(5 * time.Second):
		t.Fatalf("the push never started\nlog:\n%s", logged.String())
	}

	// Cancel while the push is mid-flight, then let it answer. The loop must still be
	// waiting for it.
	bridge.cancel()
	time.Sleep(20 * time.Millisecond)

	mu.Lock()
	early := completed
	mu.Unlock()
	if early != 0 {
		t.Fatalf("the push completed before it was released; this proves nothing")
	}

	select {
	case err := <-done:
		t.Fatalf("eventLoop returned before the in-flight push finished (err=%v); that "+
			"batch is already deleted from Salesforce\nlog:\n%s", err, logged.String())
	default:
	}

	release()

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("eventLoop returned unexpected error: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatalf("eventLoop did not return after the push finished\nlog:\n%s", logged.String())
	}

	mu.Lock()
	defer mu.Unlock()
	if completed != 1 {
		t.Errorf("the in-flight push completed %d times, want 1", completed)
	}
}
