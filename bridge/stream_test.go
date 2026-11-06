package main

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"
)

// These tests drive featureLoop in its streaming form against a fake of LaunchDarkly's
// streaming service and a fake of the org's store endpoint. What they pin is the contract
// the bridge adds on top of the eventsource library: which events change the org, which
// are ignored, when a push is skipped, how a failed push is retried, and which failures
// stop the daemon.
//
// Pushes are asserted by content rather than by count wherever a count could be lowered
// by coalescing. flagPushLoop folds every change that lands during one push into the
// next, so two events can legitimately cost one push, and a test that counted them would
// flake. The last push's payload is deterministic either way, because events are applied
// in order and pushes are serialized.

// streamFlagData is the data of the put that opens most of these tests.
const streamFlagData = `{"flags":{"alpha":{"key":"alpha","version":3},"beta":{"key":"beta","version":7}},"segments":{}}`

// streamWait bounds every wait in these tests. A stream that never does what a test
// expects should fail the test, not hang the suite.
const streamWait = 10 * time.Second

// streamServer stands in for LaunchDarkly's streaming service. Each connection is
// answered with the status statusFor picks from its one-based number; a 200 opens a stream
// the test can then write frames to and drop at will.
type streamServer struct {
	t         *testing.T
	server    *httptest.Server
	statusFor func(connection int) int

	mu          sync.Mutex
	connections int
	headers     []http.Header
	// arrivals is when each connection was accepted, by zero-based number, for tests
	// of how long the bridge waited before reconnecting.
	arrivals []time.Time
	current  *streamConnection
	// opened receives once per stream that has been accepted, so a test can wait for a
	// specific connection rather than sleep and hope.
	opened chan struct{}
	// awaited counts the connections a test has already waited for.
	awaited int
}

// streamConnection is one open stream, as the handler serving it sees it.
type streamConnection struct {
	frames chan string
	drop   chan struct{}
}

func newStreamServer(t *testing.T, statusFor func(connection int) int) *streamServer {
	t.Helper()

	if statusFor == nil {
		statusFor = func(int) int { return http.StatusOK }
	}

	s := &streamServer{t: t, statusFor: statusFor, opened: make(chan struct{}, 64)}
	s.server = httptest.NewServer(http.HandlerFunc(s.handle))
	t.Cleanup(s.server.Close)

	return s
}

func (s *streamServer) handle(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	s.connections++
	connection := s.connections
	s.headers = append(s.headers, r.Header.Clone())
	s.arrivals = append(s.arrivals, time.Now())
	status := s.statusFor(connection)
	s.mu.Unlock()

	if status != http.StatusOK {
		w.WriteHeader(status)
		_, _ = w.Write([]byte(`{"message":"refused"}`))
		return
	}

	flusher, ok := w.(http.Flusher)
	if !ok {
		s.t.Error("the test server's ResponseWriter cannot flush")
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.WriteHeader(http.StatusOK)
	flusher.Flush()

	open := &streamConnection{frames: make(chan string, 64), drop: make(chan struct{})}
	s.mu.Lock()
	s.current = open
	s.mu.Unlock()
	s.opened <- struct{}{}

	defer func() {
		s.mu.Lock()
		if s.current == open {
			s.current = nil
		}
		s.mu.Unlock()
	}()

	for {
		select {
		case frame := <-open.frames:
			_, _ = io.WriteString(w, frame)
			flusher.Flush()
		case <-open.drop:
			return
		case <-r.Context().Done():
			return
		}
	}
}

// awaitConnection waits for the next stream the server accepts and returns how many it
// has accepted so far.
func (s *streamServer) awaitConnection() int {
	s.t.Helper()

	select {
	case <-s.opened:
	case <-time.After(streamWait):
		s.t.Fatalf("the bridge did not open stream connection %d", s.awaited+1)
	}
	s.awaited++

	return s.awaited
}

// send writes one event to the open stream. The test must have awaited the connection
// first, so a frame is never written into a stream that has already been dropped.
func (s *streamServer) send(event, data string) {
	s.t.Helper()
	s.sendRaw("event: " + event + "\ndata: " + data + "\n\n")
}

// sendRaw writes bytes to the open stream verbatim, for frames that are not events.
func (s *streamServer) sendRaw(frame string) {
	s.t.Helper()

	s.mu.Lock()
	open := s.current
	s.mu.Unlock()

	if open == nil {
		s.t.Fatal("no stream connection is open to send on")
	}

	open.frames <- frame
}

// drop ends the open stream from the server's side, as a network fault would.
func (s *streamServer) drop() {
	s.t.Helper()

	s.mu.Lock()
	open := s.current
	s.current = nil
	s.mu.Unlock()

	if open == nil {
		s.t.Fatal("no stream connection is open to drop")
	}

	close(open.drop)
}

func (s *streamServer) connectionCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.connections
}

// awaitConnectionCount waits until the server has seen at least n connections, whatever
// status it answered them with. awaitConnection only reports the ones it accepted.
func (s *streamServer) awaitConnectionCount(n int) {
	s.t.Helper()

	deadline := time.Now().Add(streamWait)
	for s.connectionCount() < n {
		if time.Now().After(deadline) {
			s.t.Fatalf("the bridge opened %d stream connections, want at least %d", s.connectionCount(), n)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

// arrivalOf returns when one connection was accepted, by one-based number.
func (s *streamServer) arrivalOf(connection int) time.Time {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.arrivals[connection-1]
}

// headersOf returns the request headers of one connection, by one-based number.
func (s *streamServer) headersOf(connection int) http.Header {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.headers[connection-1]
}

// storePush records one push the fake store endpoint served.
type storePush struct {
	path    string
	headers http.Header
	body    []byte
}

// storeServer stands in for the org's store endpoint. statusFor picks the status of each
// push from its one-based number; nil accepts every push.
type storeServer struct {
	t         *testing.T
	server    *httptest.Server
	statusFor func(push int) int

	mu      sync.Mutex
	pushes  []storePush
	arrived chan struct{}
	awaited int
}

func newStoreServer(t *testing.T, statusFor func(push int) int) *storeServer {
	t.Helper()

	if statusFor == nil {
		statusFor = func(int) int { return http.StatusOK }
	}

	s := &storeServer{t: t, statusFor: statusFor, arrived: make(chan struct{}, 1024)}
	s.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Errorf("failed reading a push body: %v", err)
		}

		s.mu.Lock()
		s.pushes = append(s.pushes, storePush{path: r.URL.Path, headers: r.Header.Clone(), body: body})
		status := s.statusFor(len(s.pushes))
		s.mu.Unlock()

		w.WriteHeader(status)
		_, _ = w.Write([]byte(`{"ok":true}`))
		s.arrived <- struct{}{}
	}))
	t.Cleanup(s.server.Close)

	return s
}

// awaitPush waits for the next push and returns it.
func (s *storeServer) awaitPush() storePush {
	s.t.Helper()

	select {
	case <-s.arrived:
	case <-time.After(streamWait):
		s.t.Fatalf("the bridge did not push to Salesforce (push %d)", s.awaited+1)
	}
	s.awaited++

	s.mu.Lock()
	defer s.mu.Unlock()
	return s.pushes[s.awaited-1]
}

func (s *storeServer) pushCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.pushes)
}

// newStreamingBridge builds a test bridge that streams from ld and pushes to sf.
func newStreamingBridge(t *testing.T, ld *streamServer, sf *storeServer) *Bridge {
	t.Helper()

	bridge := newTestBridge(t, "http://unused.invalid", "http://unused.invalid")
	bridge.streaming = true
	bridge.launchDarklyStreamURI = ld.server.URL
	bridge.salesforceURL = sf.server.URL + "/"
	bridge.oauthCurrentToken = "test-token"

	return bridge
}

// startFeatureLoop runs featureLoop on its own goroutine and returns a function that
// stops the bridge and reports what the loop returned. A loop that does not return once
// the bridge is cancelled is a failure in itself, so the wait is bounded.
func startFeatureLoop(t *testing.T, bridge *Bridge) (stop func() error, done <-chan error) {
	t.Helper()

	result := make(chan error, 1)
	go func() { result <- bridge.featureLoop() }()

	return func() error {
		t.Helper()
		bridge.cancel()
		select {
		case err := <-result:
			return err
		case <-time.After(streamWait):
			t.Fatal("featureLoop did not return after the bridge was cancelled")
			return nil
		}
	}, result
}

// awaitReturn waits for a loop that is expected to stop on its own.
func awaitReturn(t *testing.T, done <-chan error) error {
	t.Helper()

	select {
	case err := <-done:
		return err
	case <-time.After(streamWait):
		t.Fatal("featureLoop did not return on its own")
		return nil
	}
}

// assertSameJSON compares two JSON documents by value, so key order and whitespace do
// not matter.
func assertSameJSON(t *testing.T, got []byte, want string) {
	t.Helper()

	var gotValue, wantValue interface{}
	if err := json.Unmarshal(got, &gotValue); err != nil {
		t.Fatalf("the push body is not JSON: %v\nbody: %s", err, got)
	}
	if err := json.Unmarshal([]byte(want), &wantValue); err != nil {
		t.Fatalf("the expected document is not JSON: %v\ndocument: %s", err, want)
	}

	if !reflect.DeepEqual(gotValue, wantValue) {
		t.Errorf("push body = %s\nwant %s", got, want)
	}
}

// TestStreamPutIsPushedToSalesforce is the end-to-end case: featureLoop opens the stream
// with the headers LaunchDarkly expects, and the put that opens the stream reaches the
// org's store endpoint as the same document a poll would have pushed.
func TestStreamPutIsPushedToSalesforce(t *testing.T) {
	captureLog(t)
	ld := newStreamServer(t, nil)
	sf := newStoreServer(t, nil)
	bridge := newStreamingBridge(t, ld, sf)
	bridge.scopeKey = "gps"

	stop, _ := startFeatureLoop(t, bridge)

	ld.awaitConnection()
	headers := ld.headersOf(1)
	if got := headers.Get("Authorization"); got != bridge.launchDarklyKey {
		t.Errorf("stream Authorization = %q, want the SDK key %q", got, bridge.launchDarklyKey)
	}
	if got := headers.Get("User-Agent"); got != USER_AGENT {
		t.Errorf("stream User-Agent = %q, want %q", got, USER_AGENT)
	}
	if got := headers.Get(INSTANCE_ID_HEADER); got != bridge.instanceID {
		t.Errorf("stream %s = %q, want %q", INSTANCE_ID_HEADER, got, bridge.instanceID)
	}
	if got := headers.Get("Accept"); got != "text/event-stream" {
		t.Errorf("stream Accept = %q, want text/event-stream", got)
	}

	ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)

	push := sf.awaitPush()
	if push.path != "/store" {
		t.Errorf("pushed to %q, want /store", push.path)
	}
	if got := push.headers.Get("Content-Type"); got != "application/json" {
		t.Errorf("push Content-Type = %q, want application/json", got)
	}
	if got := push.headers.Get("Authorization"); got != "Bearer test-token" {
		t.Errorf("push Authorization = %q, want the bearer token", got)
	}
	if got := push.headers.Get(SCOPE_HEADER); got != "gps" {
		t.Errorf("push %s = %q, want gps", SCOPE_HEADER, got)
	}
	assertSameJSON(t, push.body, streamFlagData)

	if err := stop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}
}

// TestStreamUpdatesAreVersioned covers what each event after the put does to the org.
//
// Every case ends with a patch to a key nothing else touches, so the push that carries
// it is the one to assert on: by then every earlier event has been applied or declined,
// and the payload shows which.
func TestStreamUpdatesAreVersioned(t *testing.T) {
	type frame struct{ event, data string }

	const sentinel = `"sentinel":{"key":"sentinel","version":1}`
	const alpha = `"alpha":{"key":"alpha","version":3}`
	const beta = `"beta":{"key":"beta","version":7}`

	tests := []struct {
		name   string
		events []frame
		want   string
	}{
		{
			name:   "a patch adds a flag",
			events: []frame{{PATCH_EVENT, `{"path":"/flags/gamma","data":{"key":"gamma","version":1}}`}},
			want:   `{"flags":{` + alpha + `,` + beta + `,"gamma":{"key":"gamma","version":1},` + sentinel + `},"segments":{}}`,
		},
		{
			name:   "a newer patch replaces a flag",
			events: []frame{{PATCH_EVENT, `{"path":"/flags/alpha","data":{"key":"alpha","version":4,"on":true}}`}},
			want:   `{"flags":{"alpha":{"key":"alpha","version":4,"on":true},` + beta + `,` + sentinel + `},"segments":{}}`,
		},
		{
			name:   "an older patch is ignored",
			events: []frame{{PATCH_EVENT, `{"path":"/flags/alpha","data":{"key":"alpha","version":2,"on":true}}`}},
			want:   `{"flags":{` + alpha + `,` + beta + `,` + sentinel + `},"segments":{}}`,
		},
		{
			// Equal versions are declined, which is what makes a redelivered event
			// harmless.
			name:   "a patch at the same version is ignored",
			events: []frame{{PATCH_EVENT, `{"path":"/flags/alpha","data":{"key":"alpha","version":3,"on":true}}`}},
			want:   `{"flags":{` + alpha + `,` + beta + `,` + sentinel + `},"segments":{}}`,
		},
		{
			name:   "a delete removes a flag",
			events: []frame{{DELETE_EVENT, `{"path":"/flags/alpha","version":4}`}},
			want:   `{"flags":{` + beta + `,` + sentinel + `},"segments":{}}`,
		},
		{
			name:   "an older delete is ignored",
			events: []frame{{DELETE_EVENT, `{"path":"/flags/alpha","version":2}`}},
			want:   `{"flags":{` + alpha + `,` + beta + `,` + sentinel + `},"segments":{}}`,
		},
		{
			// The tombstone at work: the patch was in flight when the flag was deleted,
			// and must not bring it back.
			name: "a patch older than a delete is ignored",
			events: []frame{
				{DELETE_EVENT, `{"path":"/flags/alpha","version":5}`},
				{PATCH_EVENT, `{"path":"/flags/alpha","data":{"key":"alpha","version":4}}`},
			},
			want: `{"flags":{` + beta + `,` + sentinel + `},"segments":{}}`,
		},
		{
			name: "a patch newer than a delete restores the flag",
			events: []frame{
				{DELETE_EVENT, `{"path":"/flags/alpha","version":5}`},
				{PATCH_EVENT, `{"path":"/flags/alpha","data":{"key":"alpha","version":6}}`},
			},
			want: `{"flags":{"alpha":{"key":"alpha","version":6},` + beta + `,` + sentinel + `},"segments":{}}`,
		},
		{
			name:   "a delete of an unknown flag leaves a tombstone",
			events: []frame{{DELETE_EVENT, `{"path":"/flags/gamma","version":9}`}, {PATCH_EVENT, `{"path":"/flags/gamma","data":{"key":"gamma","version":8}}`}},
			want:   `{"flags":{` + alpha + `,` + beta + `,` + sentinel + `},"segments":{}}`,
		},
		{
			name:   "a segment patch lands under segments",
			events: []frame{{PATCH_EVENT, `{"path":"/segments/vip","data":{"key":"vip","version":1}}`}},
			want:   `{"flags":{` + alpha + `,` + beta + `,` + sentinel + `},"segments":{"vip":{"key":"vip","version":1}}}`,
		},
		{
			name:   "a segment delete removes a segment",
			events: []frame{{PATCH_EVENT, `{"path":"/segments/vip","data":{"key":"vip","version":1}}`}, {DELETE_EVENT, `{"path":"/segments/vip","version":2}`}},
			want:   `{"flags":{` + alpha + `,` + beta + `,` + sentinel + `},"segments":{}}`,
		},
		{
			// An item kind the bridge does not know is left alone rather than treated as
			// malformed, so a new kind costs nothing.
			name:   "an unknown path is ignored",
			events: []frame{{PATCH_EVENT, `{"path":"/things/x","data":{"key":"x","version":1}}`}, {DELETE_EVENT, `{"path":"/things/y","version":1}`}},
			want:   `{"flags":{` + alpha + `,` + beta + `,` + sentinel + `},"segments":{}}`,
		},
		{
			name:   "a second put replaces everything",
			events: []frame{{PUT_EVENT, `{"path":"/","data":{"flags":{"delta":{"key":"delta","version":1}},"segments":{}}}`}},
			want:   `{"flags":{"delta":{"key":"delta","version":1},` + sentinel + `},"segments":{}}`,
		},
		{
			// Tombstones go with everything else, so a put can bring back a key that
			// was deleted before it.
			name: "a put clears tombstones",
			events: []frame{
				{DELETE_EVENT, `{"path":"/flags/alpha","version":9}`},
				{PUT_EVENT, `{"path":"/","data":` + streamFlagData + `}`},
			},
			want: `{"flags":{` + alpha + `,` + beta + `,` + sentinel + `},"segments":{}}`,
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			captureLog(t)
			ld := newStreamServer(t, nil)
			sf := newStoreServer(t, nil)
			bridge := newStreamingBridge(t, ld, sf)

			stop, _ := startFeatureLoop(t, bridge)

			ld.awaitConnection()
			ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)
			assertSameJSON(t, sf.awaitPush().body, streamFlagData)

			for _, event := range test.events {
				ld.send(event.event, event.data)
			}
			ld.send(PATCH_EVENT, `{"path":"/flags/sentinel","data":{"key":"sentinel","version":1}}`)

			// The sentinel is the last event, so the last push to carry it is the
			// final state. Earlier pushes may or may not exist, depending on how the
			// changes coalesced.
			var last storePush
			for {
				last = sf.awaitPush()
				if strings.Contains(string(last.body), `"sentinel"`) {
					break
				}
			}
			assertSameJSON(t, last.body, test.want)

			if err := stop(); err != nil {
				t.Fatalf("featureLoop returned unexpected error: %v", err)
			}
			if connections := ld.connectionCount(); connections != 1 {
				t.Errorf("the bridge opened %d stream connections, want 1; nothing here should restart the stream", connections)
			}
		})
	}
}

// TestStreamIgnoresWhatItDoesNotUnderstand covers events and frames that must change
// nothing: an event type the bridge has no handler for, and a comment, which is what
// LaunchDarkly's heartbeat is. Neither restarts the stream and neither pushes.
func TestStreamIgnoresWhatItDoesNotUnderstand(t *testing.T) {
	logged := captureLog(t)
	ld := newStreamServer(t, nil)
	sf := newStoreServer(t, nil)
	bridge := newStreamingBridge(t, ld, sf)

	stop, _ := startFeatureLoop(t, bridge)

	ld.awaitConnection()
	ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)
	assertSameJSON(t, sf.awaitPush().body, streamFlagData)

	ld.sendRaw(":heartbeat\n\n")
	ld.send("goodbye", `{"reason":"testing"}`)
	ld.send(PATCH_EVENT, `{"path":"/flags/sentinel","data":{"key":"sentinel","version":1}}`)

	push := sf.awaitPush()
	if !strings.Contains(string(push.body), `"sentinel"`) {
		t.Errorf("the push after the unknown event is not the sentinel's: %s", push.body)
	}

	if err := stop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}
	if connections := ld.connectionCount(); connections != 1 {
		t.Errorf("the bridge opened %d stream connections, want 1", connections)
	}
	if !strings.Contains(logged.String(), `ignoring an unexpected "goodbye" event`) {
		t.Errorf("the unknown event was not logged\nlog:\n%s", logged.String())
	}
}

// TestStreamMalformedEventRestartsTheStream covers the response to data the bridge
// cannot apply. It cannot know what the event would have changed, so it drops the
// connection, and the connection that replaces it opens with a complete put.
func TestStreamMalformedEventRestartsTheStream(t *testing.T) {
	tests := []struct {
		name  string
		event string
		data  string
	}{
		{name: "put that is not JSON", event: PUT_EVENT, data: `{`},
		{name: "put without data", event: PUT_EVENT, data: `{"path":"/"}`},
		{name: "put whose item is not an object", event: PUT_EVENT, data: `{"path":"/","data":{"flags":{"x":5},"segments":{}}}`},
		{name: "put whose item is null", event: PUT_EVENT, data: `{"path":"/","data":{"flags":{"x":null},"segments":{}}}`},
		{name: "patch that is not JSON", event: PATCH_EVENT, data: `not json`},
		{name: "patch without a path", event: PATCH_EVENT, data: `{"data":{"key":"x","version":1}}`},
		{name: "patch without data", event: PATCH_EVENT, data: `{"path":"/flags/x"}`},
		{name: "patch whose data is not an object", event: PATCH_EVENT, data: `{"path":"/flags/x","data":[1,2]}`},
		{name: "delete without a path", event: DELETE_EVENT, data: `{"version":1}`},
		{name: "delete without a version", event: DELETE_EVENT, data: `{"path":"/flags/x"}`},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			logged := captureLog(t)
			ld := newStreamServer(t, nil)
			sf := newStoreServer(t, nil)
			bridge := newStreamingBridge(t, ld, sf)

			stop, _ := startFeatureLoop(t, bridge)

			ld.awaitConnection()
			ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)
			assertSameJSON(t, sf.awaitPush().body, streamFlagData)

			ld.send(test.event, test.data)

			if got := ld.awaitConnection(); got != 2 {
				t.Fatalf("awaited connection 2, got %d", got)
			}

			// The fresh connection's put is what makes the restart worth anything,
			// and it must be applied like any other: a changed set gets pushed.
			changed := `{"flags":{"gamma":{"key":"gamma","version":1}},"segments":{}}`
			ld.send(PUT_EVENT, `{"path":"/","data":`+changed+`}`)
			assertSameJSON(t, sf.awaitPush().body, changed)

			if err := stop(); err != nil {
				t.Fatalf("featureLoop returned unexpected error: %v", err)
			}
			if !strings.Contains(logged.String(), "malformed data") {
				t.Errorf("the malformed event was not logged\nlog:\n%s", logged.String())
			}
		})
	}
}

// TestStreamReconnectWithUnchangedDataPushesNothing covers the dedupe that makes a
// flapping connection cheap. Every reconnect opens with a put, and after a brief
// interruption that put is what the org already has.
func TestStreamReconnectWithUnchangedDataPushesNothing(t *testing.T) {
	logged := captureLog(t)
	ld := newStreamServer(t, nil)
	sf := newStoreServer(t, nil)
	bridge := newStreamingBridge(t, ld, sf)

	stop, _ := startFeatureLoop(t, bridge)

	ld.awaitConnection()
	ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)
	assertSameJSON(t, sf.awaitPush().body, streamFlagData)

	ld.drop()
	ld.awaitConnection()

	// The same data with every object's keys in a different order, including the keys
	// inside each item, which is how LaunchDarkly really does send the same flag on two
	// connections. The bridge compares content, not the bytes off the wire.
	ld.send(PUT_EVENT, `{"path":"/","data":{"segments":{},"flags":{"beta":{"version":7,"key":"beta"},"alpha":{"version":3,"key":"alpha"}}}}`)

	// The decision not to push is observable only in the log, so wait for it there. A
	// sentinel sent straight after the put would prove nothing: the push loop can fold
	// the two into one push, and that push would carry the sentinel either way.
	const skipped = "flag data is unchanged from the last push"
	deadline := time.Now().Add(streamWait)
	for !strings.Contains(logged.String(), skipped) {
		if time.Now().After(deadline) {
			t.Fatalf("the bridge never reported skipping the push\nlog:\n%s", logged.String())
		}
		time.Sleep(5 * time.Millisecond)
	}
	if pushes := sf.pushCount(); pushes != 1 {
		t.Errorf("Salesforce served %d pushes, want 1; the identical put after a reconnect was pushed", pushes)
	}

	// The loop is still delivering: a real change after the skipped one goes out.
	ld.send(PATCH_EVENT, `{"path":"/flags/sentinel","data":{"key":"sentinel","version":1}}`)
	push := sf.awaitPush()
	if !strings.Contains(string(push.body), `"sentinel"`) {
		t.Errorf("the push after the skipped one is not the sentinel's: %s", push.body)
	}

	if err := stop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}
}

// TestStreamPatchBeforePutIsIgnored covers the guard against pushing an incomplete set.
// The stream always opens with a put, so a patch ahead of one is a protocol violation,
// and a set assembled from it alone would replace whatever complete set the org holds.
func TestStreamPatchBeforePutIsIgnored(t *testing.T) {
	captureLog(t)
	ld := newStreamServer(t, nil)
	sf := newStoreServer(t, nil)
	bridge := newStreamingBridge(t, ld, sf)

	stop, _ := startFeatureLoop(t, bridge)

	ld.awaitConnection()
	ld.send(PATCH_EVENT, `{"path":"/flags/gamma","data":{"key":"gamma","version":1}}`)
	ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)

	// The first push is the put's, and it does not contain the early patch.
	assertSameJSON(t, sf.awaitPush().body, streamFlagData)

	if err := stop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}
}

// TestStreamPushRetriesUntilSalesforceAccepts covers what a stream has that a poll does
// not need: its own retry. A poll that failed to push tries again next cycle; a stream
// has no next cycle until the flag changes again.
func TestStreamPushRetriesUntilSalesforceAccepts(t *testing.T) {
	logged := captureLog(t)
	ld := newStreamServer(t, nil)
	sf := newStoreServer(t, func(push int) int {
		switch push {
		case 1:
			return http.StatusInternalServerError
		case 2:
			return http.StatusServiceUnavailable
		default:
			return http.StatusOK
		}
	})
	bridge := newStreamingBridge(t, ld, sf)

	stop, _ := startFeatureLoop(t, bridge)

	ld.awaitConnection()
	ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)

	for attempt := 1; attempt <= 3; attempt++ {
		push := sf.awaitPush()
		assertSameJSON(t, push.body, streamFlagData)
	}

	if err := stop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}
	if !strings.Contains(logged.String(), "failed pushing flags to salesforce") {
		t.Errorf("the failed push was not logged\nlog:\n%s", logged.String())
	}
}

// TestStreamPushRetryCarriesNewerData covers the coalescing on the retry path. A change
// that lands while a failed push waits to be retried goes out in the retry, folded in
// rather than queued behind the stale snapshot -- but not before the retry was due. The
// delay is there to spare an org that is refusing pushes, and an org that has hit its
// API limit answers every push with a 403, so letting a change cut the delay short would
// push at the rate flags change rather than at the backoff rate.
func TestStreamPushRetryCarriesNewerData(t *testing.T) {
	captureLog(t)
	ld := newStreamServer(t, nil)
	sf := newStoreServer(t, func(push int) int {
		if push == 1 {
			return http.StatusInternalServerError
		}
		return http.StatusOK
	})
	bridge := newStreamingBridge(t, ld, sf)
	// Long enough to measure, short enough that a change can be sent during it.
	const retryDelay = 500 * time.Millisecond
	bridge.dataPushRetryDelay = retryDelay

	stop, _ := startFeatureLoop(t, bridge)

	ld.awaitConnection()
	ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)
	assertSameJSON(t, sf.awaitPush().body, streamFlagData)
	refused := time.Now()

	ld.send(PATCH_EVENT, `{"path":"/flags/gamma","data":{"key":"gamma","version":1}}`)

	retry := sf.awaitPush()
	assertSameJSON(t, retry.body,
		`{"flags":{"alpha":{"key":"alpha","version":3},"beta":{"key":"beta","version":7},"gamma":{"key":"gamma","version":1}},"segments":{}}`)
	// The timer started when the refusal came back, which is a little after the fake
	// store saw the push, so the wait is measured generously.
	if waited := time.Since(refused); waited < retryDelay/2 {
		t.Errorf("the retry arrived %s after the refusal; the change must not cut the %s delay short", waited, retryDelay)
	}

	if err := stop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}
	if pushes := sf.pushCount(); pushes != 2 {
		t.Errorf("Salesforce served %d pushes, want 2: the refused one and the retry carrying the change", pushes)
	}
}

// TestStreamFailedPushForgetsWhatTheOrgHolds covers the dedupe after a failure. A push
// that failed on this side may have been committed on the org's side -- a timeout or a
// 5xx says nothing either way -- so if the data then goes back to what was last pushed
// successfully, it has to be pushed again rather than skipped as unchanged.
func TestStreamFailedPushForgetsWhatTheOrgHolds(t *testing.T) {
	captureLog(t)
	ld := newStreamServer(t, nil)
	sf := newStoreServer(t, func(push int) int {
		if push == 2 {
			return http.StatusInternalServerError
		}
		return http.StatusOK
	})
	bridge := newStreamingBridge(t, ld, sf)
	// Long enough that the revert below lands while the failed push is waiting to be
	// retried, so the retry is what carries it.
	bridge.dataPushRetryDelay = 500 * time.Millisecond

	stop, _ := startFeatureLoop(t, bridge)

	ld.awaitConnection()
	ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)
	assertSameJSON(t, sf.awaitPush().body, streamFlagData)

	// A change the org refuses, and then, by way of a reconnect, the data as it was
	// before the change.
	ld.send(PATCH_EVENT, `{"path":"/flags/gamma","data":{"key":"gamma","version":1}}`)
	refused := sf.awaitPush()
	if !strings.Contains(string(refused.body), `"gamma"`) {
		t.Fatalf("the second push does not carry the change: %s", refused.body)
	}
	ld.drop()
	ld.awaitConnection()
	ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)

	// Without the fix there is no third push: the reverted data matches the last
	// successful push and is skipped, and the org stays on whatever the refused push
	// left it with.
	assertSameJSON(t, sf.awaitPush().body, streamFlagData)

	if err := stop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}
	if pushes := sf.pushCount(); pushes != 3 {
		t.Errorf("Salesforce served %d pushes, want 3", pushes)
	}
}

// TestStreamPushesAreRateLimited covers the floor between pushes. LaunchDarkly sends one
// patch per changed item, so a bulk edit arrives as a burst, and every push is a
// Salesforce API call against the org's daily allocation. Changes that land within the
// interval after a push are held and go out together once it has passed.
func TestStreamPushesAreRateLimited(t *testing.T) {
	logged := captureLog(t)
	ld := newStreamServer(t, nil)
	sf := newStoreServer(t, nil)
	bridge := newStreamingBridge(t, ld, sf)
	const interval = 500 * time.Millisecond
	bridge.dataPushMinInterval = interval

	stop, _ := startFeatureLoop(t, bridge)

	// The first push is not held: nothing came before it.
	ld.awaitConnection()
	ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)
	assertSameJSON(t, sf.awaitPush().body, streamFlagData)
	first := time.Now()

	// A burst. Three changes, one push.
	ld.send(PATCH_EVENT, `{"path":"/flags/gamma","data":{"key":"gamma","version":1}}`)
	ld.send(PATCH_EVENT, `{"path":"/flags/delta","data":{"key":"delta","version":1}}`)
	ld.send(PATCH_EVENT, `{"path":"/flags/alpha","data":{"key":"alpha","version":4}}`)

	second := sf.awaitPush()
	assertSameJSON(t, second.body,
		`{"flags":{"alpha":{"key":"alpha","version":4},"beta":{"key":"beta","version":7},"gamma":{"key":"gamma","version":1},"delta":{"key":"delta","version":1}},"segments":{}}`)
	// The interval is measured from when the first push finished, which is a little
	// after the fake store saw it, so the wait is measured generously.
	if waited := time.Since(first); waited < interval/2 {
		t.Errorf("the second push arrived %s after the first, want at least %s", waited, interval)
	}

	if err := stop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}
	if pushes := sf.pushCount(); pushes != 2 {
		t.Errorf("Salesforce served %d pushes, want 2: the put and one carrying the whole burst", pushes)
	}
	if !strings.Contains(logged.String(), "holding the flag push for") {
		t.Errorf("the hold was not logged\nlog:\n%s", logged.String())
	}
}

// TestStreamSlowsDownOnAnUnrecoverableStatus covers the statuses a retry is unlikely to
// change. The daemon does not stop -- a stop would need an operator to notice, and would
// take event delivery down with flag delivery -- but it does not keep asking every second
// either: the reconnects move onto the extended schedule, and the stream resumes when the
// service answers 200 again.
func TestStreamSlowsDownOnAnUnrecoverableStatus(t *testing.T) {
	// Long enough to tell from the millisecond reconnect delay the test bridge uses,
	// short enough that two of them fit in a test. With jitter, each wait is at least
	// half of this.
	const extended = 200 * time.Millisecond

	tests := []struct {
		name string
		// statusFor answers each connection. The unrecoverable status is reached on the
		// first connection or after one good one, since the two go through different
		// paths in the stream library, and is answered twice so the second wait shows
		// the backoff holding.
		statusFor func(connection int) int
		// refused is the first connection answered with the unrecoverable status.
		refused int
		wantLog string
	}{
		{
			name: "401 on the first connection",
			statusFor: func(connection int) int {
				if connection <= 2 {
					return http.StatusUnauthorized
				}
				return http.StatusOK
			},
			refused: 1,
			wantLog: "refused the SDK key with HTTP 401; check LD_SDK_KEY",
		},
		{
			name: "403 on the first connection",
			statusFor: func(connection int) int {
				if connection <= 2 {
					return http.StatusForbidden
				}
				return http.StatusOK
			},
			refused: 1,
			wantLog: "refused the SDK key with HTTP 403; check LD_SDK_KEY",
		},
		{
			name: "404 on the first connection",
			statusFor: func(connection int) int {
				if connection <= 2 {
					return http.StatusNotFound
				}
				return http.StatusOK
			},
			refused: 1,
			wantLog: "answered HTTP 404, which a retry is unlikely to fix; check LD_STREAM_URI",
		},
		{
			name: "401 after a reconnect",
			statusFor: func(connection int) int {
				switch connection {
				case 1:
					return http.StatusOK
				case 2, 3:
					return http.StatusUnauthorized
				default:
					return http.StatusOK
				}
			},
			refused: 2,
			wantLog: "refused the SDK key with HTTP 401; check LD_SDK_KEY",
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			logged := captureLog(t)
			ld := newStreamServer(t, test.statusFor)
			sf := newStoreServer(t, nil)
			bridge := newStreamingBridge(t, ld, sf)
			bridge.streamExtendedRetryDelay = extended

			stop, done := startFeatureLoop(t, bridge)

			if test.refused > 1 {
				ld.awaitConnection()
				ld.drop()
			}

			// Two refusals, then the connection that is accepted.
			ld.awaitConnectionCount(test.refused + 2)
			ld.awaitConnection()

			if waited := ld.arrivalOf(test.refused + 1).Sub(ld.arrivalOf(test.refused)); waited < extended/2 {
				t.Errorf("the first retry came %s after the refusal, want at least %s: the extended delay was not used", waited, extended/2)
			}
			if waited := ld.arrivalOf(test.refused + 2).Sub(ld.arrivalOf(test.refused + 1)); waited < extended {
				t.Errorf("the second retry came %s after the first, want at least %s: the extended delay did not back off", waited, extended)
			}

			// The daemon is still running, and the stream that was finally accepted is
			// used.
			select {
			case err := <-done:
				t.Fatalf("featureLoop returned (%v) on a status that must not stop the daemon", err)
			default:
			}
			if bridge.context.Err() != nil {
				t.Error("the bridge was cancelled; eventLoop would have stopped too")
			}
			ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)
			assertSameJSON(t, sf.awaitPush().body, streamFlagData)

			if err := stop(); err != nil {
				t.Fatalf("featureLoop returned unexpected error: %v", err)
			}
			if !strings.Contains(logged.String(), test.wantLog) {
				t.Errorf("the log does not contain %q\nlog:\n%s", test.wantLog, logged.String())
			}
		})
	}
}

// TestStreamRecoverableStatusRestoresTheNormalDelay is the other side of the extended
// schedule. A service that answered 404 and now answers 503 is answering differently,
// so the next reconnect is on the normal schedule rather than minutes away.
func TestStreamRecoverableStatusRestoresTheNormalDelay(t *testing.T) {
	const extended = time.Second

	captureLog(t)
	ld := newStreamServer(t, func(connection int) int {
		switch connection {
		case 1:
			return http.StatusNotFound
		case 2:
			return http.StatusServiceUnavailable
		default:
			return http.StatusOK
		}
	})
	sf := newStoreServer(t, nil)
	bridge := newStreamingBridge(t, ld, sf)
	bridge.streamExtendedRetryDelay = extended

	stop, _ := startFeatureLoop(t, bridge)

	ld.awaitConnection()
	if waited := ld.arrivalOf(2).Sub(ld.arrivalOf(1)); waited < extended/2 {
		t.Errorf("the retry after the 404 came %s later, want at least %s", waited, extended/2)
	}
	if waited := ld.arrivalOf(3).Sub(ld.arrivalOf(2)); waited >= extended/2 {
		t.Errorf("the retry after the 503 came %s later; the extended delay was still in force", waited)
	}

	if err := stop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}
}

// TestStreamRetriesARecoverableStatus is the other half: a status that may answer
// differently next time gets a reconnect, and the stream that eventually opens is used.
func TestStreamRetriesARecoverableStatus(t *testing.T) {
	captureLog(t)
	ld := newStreamServer(t, func(connection int) int {
		switch connection {
		case 1:
			return http.StatusServiceUnavailable
		case 2:
			return http.StatusTooManyRequests
		case 3:
			return http.StatusBadRequest
		default:
			return http.StatusOK
		}
	})
	sf := newStoreServer(t, nil)
	bridge := newStreamingBridge(t, ld, sf)

	stop, _ := startFeatureLoop(t, bridge)

	ld.awaitConnection()
	ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)
	assertSameJSON(t, sf.awaitPush().body, streamFlagData)

	if err := stop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}
	if connections := ld.connectionCount(); connections != 4 {
		t.Errorf("the bridge opened %d stream connections, want 4", connections)
	}
}

// TestStreamReconnectsAfterSilence covers the read timeout. A connection the far end has
// abandoned without closing looks exactly like a quiet one, so silence past the timeout
// is treated as a dead connection.
func TestStreamReconnectsAfterSilence(t *testing.T) {
	captureLog(t)
	ld := newStreamServer(t, nil)
	sf := newStoreServer(t, nil)
	bridge := newStreamingBridge(t, ld, sf)
	bridge.streamReadTimeout = 50 * time.Millisecond

	stop, _ := startFeatureLoop(t, bridge)

	// The server accepts and then says nothing, twice over.
	ld.awaitConnection()
	ld.awaitConnection()

	if err := stop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}
}

// TestStreamShutdownIsPrompt covers cancellation in each state the stream can be in:
// connected and idle, and waiting out a reconnect delay. Neither may hold the process
// open, and neither is an error.
func TestStreamShutdownIsPrompt(t *testing.T) {
	t.Run("while connected", func(t *testing.T) {
		captureLog(t)
		ld := newStreamServer(t, nil)
		sf := newStoreServer(t, nil)
		bridge := newStreamingBridge(t, ld, sf)

		stop, _ := startFeatureLoop(t, bridge)
		ld.awaitConnection()

		started := time.Now()
		if err := stop(); err != nil {
			t.Fatalf("featureLoop returned unexpected error: %v", err)
		}
		if took := time.Since(started); took > 2*time.Second {
			t.Errorf("shutdown took %s while connected", took)
		}
	})

	t.Run("while waiting to reconnect", func(t *testing.T) {
		captureLog(t)
		ld := newStreamServer(t, func(int) int { return http.StatusServiceUnavailable })
		sf := newStoreServer(t, nil)
		bridge := newStreamingBridge(t, ld, sf)
		// Long enough that a shutdown waiting out the delay would fail the test.
		bridge.streamInitialReconnectDelay = time.Hour

		stop, _ := startFeatureLoop(t, bridge)

		// Give the first attempt time to be refused and the wait to begin.
		deadline := time.Now().Add(streamWait)
		for ld.connectionCount() < 1 && time.Now().Before(deadline) {
			time.Sleep(5 * time.Millisecond)
		}

		started := time.Now()
		if err := stop(); err != nil {
			t.Fatalf("featureLoop returned unexpected error: %v", err)
		}
		if took := time.Since(started); took > 2*time.Second {
			t.Errorf("shutdown took %s while waiting to reconnect", took)
		}
	})
}

// TestStreamStopsOnAPermanentSalesforceFailure covers the push side's one fatal outcome.
// A push refused with a token that was just refreshed, and a refresh Salesforce rejects
// outright, means the credential cannot work, and the daemon stops the way the polling
// loop always has.
func TestStreamStopsOnAPermanentSalesforceFailure(t *testing.T) {
	captureLog(t)
	ld := newStreamServer(t, nil)
	sf := newStoreServer(t, func(int) int { return http.StatusUnauthorized })

	// The token endpoint rejects the credential, which authorizeSalesforce reports as
	// permanent.
	tokens := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"invalid_client"}`))
	}))
	defer tokens.Close()

	// newBridge resolved a polling bridge, so the stream state is prepared here.
	bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokens.URL)
	t.Cleanup(bridge.cancel)
	bridge.streaming = true
	bridge.launchDarklyStreamURI = ld.server.URL
	bridge.salesforceURL = sf.server.URL + "/"
	bridge.oauthCurrentToken = staleToken
	bridge.initDataStream(0)
	bridge.streamInitialReconnectDelay = time.Millisecond
	bridge.streamExtendedRetryDelay = time.Millisecond
	bridge.streamReadTimeout = STREAM_READ_TIMEOUT
	bridge.dataPushRetryDelay = time.Millisecond

	_, done := startFeatureLoop(t, bridge)

	ld.awaitConnection()
	ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)

	err := awaitReturn(t, done)
	if err == nil {
		t.Fatal("featureLoop returned nil after Salesforce rejected the credential")
	}
	if err.Error() != "Feature push Salesforce OAuth failure" {
		t.Errorf("featureLoop returned %q, want the OAuth failure", err)
	}
}

// TestStreamReturnsAPushRequestError is the streaming counterpart of
// TestFeatureLoopReturnsAPushRequestError: a push URI the request cannot be built from
// stops the loop with the underlying error, since no retry can build it either.
func TestStreamReturnsAPushRequestError(t *testing.T) {
	captureLog(t)
	ld := newStreamServer(t, nil)
	sf := newStoreServer(t, nil)
	bridge := newStreamingBridge(t, ld, sf)
	bridge.salesforceURL = "http://salesforce.invalid/\x7f/"

	wantErr := requestConstructionError(t, "POST", bridge.salesforceURL+"store")

	_, done := startFeatureLoop(t, bridge)

	ld.awaitConnection()
	ld.send(PUT_EVENT, `{"path":"/","data":`+streamFlagData+`}`)

	err := awaitReturn(t, done)
	if err == nil {
		t.Fatal("featureLoop returned nil for an unbuildable push request")
	}
	if err.Error() != wantErr.Error() {
		t.Errorf("featureLoop returned %q, want the underlying error %q", err, wantErr)
	}
}

// TestNewBridgeResolvesStreaming covers FLAG_STREAMING through newBridge. Polling is
// the default, as it was before streaming existed; a value that is not a boolean keeps
// the default rather than failing startup, matching how the duration variables behave.
func TestNewBridgeResolvesStreaming(t *testing.T) {
	tests := []struct {
		name    string
		value   string
		set     bool
		want    bool
		wantLog string
	}{
		{name: "unset polls", set: false, want: false, wantLog: "delivering flags by polling " + LD_BASE_URI + " every 30s"},
		{name: "empty polls", value: "", set: true, want: false},
		{name: "false polls", value: "false", set: true, want: false},
		{name: "true streams", value: "true", set: true, want: true, wantLog: "delivering flags by streaming from " + LD_STREAM_URI + ", pushing to Salesforce at most every 5s"},
		{name: "1 streams", value: "1", set: true, want: true},
		{name: "TRUE streams", value: "TRUE", set: true, want: true},
		{name: "surrounding whitespace is trimmed", value: " true ", set: true, want: true},
		{name: "a non-boolean keeps the default", value: "yes", set: true, want: false, wantLog: "FLAG_STREAMING (yes) is not a boolean, using false"},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			setMinimalBridgeEnv(t)
			if test.set {
				setEnv(t, "FLAG_STREAMING", test.value)
			} else {
				unsetEnv(t, "FLAG_STREAMING")
			}
			logged := captureLog(t)

			bridge, err := newBridge()
			if err != nil {
				t.Fatalf("newBridge returned unexpected error: %v", err)
			}
			if bridge.streaming != test.want {
				t.Errorf("streaming = %v, want %v", bridge.streaming, test.want)
			}
			if test.wantLog != "" && !strings.Contains(logged.String(), test.wantLog) {
				t.Errorf("startup log does not contain %q\nlog:\n%s", test.wantLog, logged.String())
			}
		})
	}
}

// TestNewBridgeResolvesStreamURI covers LD_STREAM_URI.
func TestNewBridgeResolvesStreamURI(t *testing.T) {
	setMinimalBridgeEnv(t)
	unsetEnv(t, "LD_STREAM_URI")

	bridge, err := newBridge()
	if err != nil {
		t.Fatalf("newBridge returned unexpected error: %v", err)
	}
	if bridge.launchDarklyStreamURI != LD_STREAM_URI {
		t.Errorf("launchDarklyStreamURI = %q, want the default %q", bridge.launchDarklyStreamURI, LD_STREAM_URI)
	}

	setEnv(t, "LD_STREAM_URI", "https://relay.example.invalid")
	bridge, err = newBridge()
	if err != nil {
		t.Fatalf("newBridge returned unexpected error: %v", err)
	}
	if bridge.launchDarklyStreamURI != "https://relay.example.invalid" {
		t.Errorf("launchDarklyStreamURI = %q, want the configured value", bridge.launchDarklyStreamURI)
	}
}

// TestNewBridgeResolvesStreamReconnectDelay covers STREAM_INITIAL_RECONNECT_DELAY. The
// only rule is that it be positive: the stream library honors a zero delay as zero, which
// during a LaunchDarkly outage would be a hot loop of reconnection attempts.
func TestNewBridgeResolvesStreamReconnectDelay(t *testing.T) {
	tests := []struct {
		name  string
		value string
		set   bool
		want  time.Duration
	}{
		{name: "unset falls back to the default", set: false, want: DEFAULT_STREAM_INITIAL_RECONNECT_DELAY},
		{name: "a positive value is honored", value: "250ms", set: true, want: 250 * time.Millisecond},
		{name: "zero falls back to the default", value: "0s", set: true, want: DEFAULT_STREAM_INITIAL_RECONNECT_DELAY},
		{name: "negative falls back to the default", value: "-1s", set: true, want: DEFAULT_STREAM_INITIAL_RECONNECT_DELAY},
		{name: "unparseable falls back to the default", value: "1", set: true, want: DEFAULT_STREAM_INITIAL_RECONNECT_DELAY},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			setMinimalBridgeEnv(t)
			setEnv(t, "FLAG_STREAMING", "true")
			if test.set {
				setEnv(t, "STREAM_INITIAL_RECONNECT_DELAY", test.value)
			} else {
				unsetEnv(t, "STREAM_INITIAL_RECONNECT_DELAY")
			}

			bridge, err := newBridge()
			if err != nil {
				t.Fatalf("newBridge returned unexpected error: %v", err)
			}
			if bridge.streamInitialReconnectDelay != test.want {
				t.Errorf("streamInitialReconnectDelay = %s, want %s", bridge.streamInitialReconnectDelay, test.want)
			}
		})
	}
}

// TestNewBridgeResolvesMinPushInterval covers STREAM_MIN_PUSH_INTERVAL. The default is
// the shortest value that does not warn. Anything shorter, down to zero, which removes
// the floor, is honored with the same warning a short event interval earns, since it
// lets a burst of changes cost the org more calls; only a negative or unparseable value
// falls back to the default.
func TestNewBridgeResolvesMinPushInterval(t *testing.T) {
	const warning = "is below 5s, a burst of flag changes may trigger organization wide API limits"

	tests := []struct {
		name        string
		value       string
		set         bool
		want        time.Duration
		wantWarning bool
	}{
		{name: "unset falls back to the default", set: false, want: DEFAULT_STREAM_MIN_PUSH_INTERVAL},
		{name: "a longer value is honored", value: "30s", set: true, want: 30 * time.Second},
		{name: "a shorter value is honored, with a warning", value: "2s", set: true, want: 2 * time.Second, wantWarning: true},
		{name: "zero removes the floor, with a warning", value: "0s", set: true, want: 0, wantWarning: true},
		{name: "negative falls back to the default", value: "-1s", set: true, want: DEFAULT_STREAM_MIN_PUSH_INTERVAL},
		{name: "unparseable falls back to the default", value: "30", set: true, want: DEFAULT_STREAM_MIN_PUSH_INTERVAL},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			setMinimalBridgeEnv(t)
			setEnv(t, "FLAG_STREAMING", "true")
			if test.set {
				setEnv(t, "STREAM_MIN_PUSH_INTERVAL", test.value)
			} else {
				unsetEnv(t, "STREAM_MIN_PUSH_INTERVAL")
			}
			logged := captureLog(t)

			bridge, err := newBridge()
			if err != nil {
				t.Fatalf("newBridge returned unexpected error: %v", err)
			}
			if bridge.dataPushMinInterval != test.want {
				t.Errorf("dataPushMinInterval = %s, want %s", bridge.dataPushMinInterval, test.want)
			}
			if got := strings.Contains(logged.String(), warning); got != test.wantWarning {
				t.Errorf("warning present = %v, want %v\nlog:\n%s", got, test.wantWarning, logged.String())
			}
		})
	}
}

// TestStreamingReportsAnIgnoredPollInterval covers the notice for an operator who set
// FLAG_POLL_INTERVAL expecting it to mean something with streaming on.
func TestStreamingReportsAnIgnoredPollInterval(t *testing.T) {
	const notice = "FLAG_POLL_INTERVAL has no effect while FLAG_STREAMING is on"

	tests := []struct {
		name       string
		streaming  string
		interval   string
		wantNotice bool
	}{
		{name: "streaming with an interval", streaming: "true", interval: "5m", wantNotice: true},
		{name: "streaming without an interval", streaming: "true", interval: "", wantNotice: false},
		{name: "polling with an interval", streaming: "false", interval: "5m", wantNotice: false},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			setMinimalBridgeEnv(t)
			setEnv(t, "FLAG_STREAMING", test.streaming)
			if test.interval != "" {
				setEnv(t, "FLAG_POLL_INTERVAL", test.interval)
			} else {
				unsetEnv(t, "FLAG_POLL_INTERVAL")
			}
			logged := captureLog(t)

			if _, err := newBridge(); err != nil {
				t.Fatalf("newBridge returned unexpected error: %v", err)
			}

			if got := strings.Contains(logged.String(), notice); got != test.wantNotice {
				t.Errorf("notice present = %v, want %v\nlog:\n%s", got, test.wantNotice, logged.String())
			}
		})
	}
}

// TestStreamClientBoundsOnlyTheConnection covers why the stream has its own HTTP client.
// http.Client.Timeout bounds the whole response, and a stream's response never ends, so
// HTTP_TIMEOUT has to land on getting connected instead: the dial, the TLS handshake,
// and the wait for headers, each of which can hang on its own.
func TestStreamClientBoundsOnlyTheConnection(t *testing.T) {
	defaultTransport := http.DefaultTransport.(*http.Transport)

	tests := []struct {
		name        string
		httpTimeout string
		set         bool
		wantHeader  time.Duration
		wantTLS     time.Duration
	}{
		{name: "the default", set: false, wantHeader: HTTP_TIMEOUT, wantTLS: HTTP_TIMEOUT},
		{name: "a configured timeout", httpTimeout: "1500ms", set: true, wantHeader: 1500 * time.Millisecond, wantTLS: 1500 * time.Millisecond},
		// Zero means no timeout for the main client. The stream keeps the default
		// transport's connect timeouts rather than none at all.
		{name: "zero keeps the transport defaults", httpTimeout: "0s", set: true, wantHeader: 0, wantTLS: defaultTransport.TLSHandshakeTimeout},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			setMinimalBridgeEnv(t)
			setEnv(t, "FLAG_STREAMING", "true")
			if test.set {
				setEnv(t, "HTTP_TIMEOUT", test.httpTimeout)
			}

			bridge, err := newBridge()
			if err != nil {
				t.Fatalf("newBridge returned unexpected error: %v", err)
			}

			if bridge.streamClient.Timeout != 0 {
				t.Errorf("streamClient.Timeout = %s, want 0; it would end every stream after that long",
					bridge.streamClient.Timeout)
			}
			transport, ok := bridge.streamClient.Transport.(*http.Transport)
			if !ok {
				t.Fatalf("streamClient.Transport is %T, want *http.Transport", bridge.streamClient.Transport)
			}
			if transport.ResponseHeaderTimeout != test.wantHeader {
				t.Errorf("ResponseHeaderTimeout = %s, want %s", transport.ResponseHeaderTimeout, test.wantHeader)
			}
			if transport.TLSHandshakeTimeout != test.wantTLS {
				t.Errorf("TLSHandshakeTimeout = %s, want %s", transport.TLSHandshakeTimeout, test.wantTLS)
			}
			if transport.DialContext == nil {
				t.Error("the stream transport has no dialer")
			}
			if transport.Proxy == nil {
				t.Error("the stream transport lost the default proxy configuration")
			}
		})
	}

	// The value checks above cannot see the dial timeout, so the connect phase is
	// exercised for real: a listener that accepts the connection and then says nothing
	// leaves a TLS handshake hanging, which the default transport would wait ten
	// seconds on.
	t.Run("a hung connect fails within the timeout", func(t *testing.T) {
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			t.Fatal(err)
		}
		defer listener.Close()
		go func() {
			for {
				conn, err := listener.Accept()
				if err != nil {
					return
				}
				defer conn.Close()
			}
		}()

		const timeout = 200 * time.Millisecond
		client := newStreamClient(timeout)
		started := time.Now()
		response, err := client.Get("https://" + listener.Addr().String() + "/all")
		if err == nil {
			response.Body.Close()
			t.Fatal("the request to a server that never completes the handshake succeeded")
		}
		if took := time.Since(started); took > 5*timeout {
			t.Errorf("the connect took %s to fail, want about %s", took, timeout)
		}
	})
}

// TestCanonicalJSONComparesContent pins what the dedupe in flagPushLoop depends on. Two
// stores holding the same items must compare equal however the items' keys were ordered
// on the wire and however they were spaced, and the snapshot itself must still carry each
// item as it arrived. A real difference in content must still show.
func TestCanonicalJSONComparesContent(t *testing.T) {
	var first, second dataStore

	if err := first.replace(map[string]map[string]json.RawMessage{
		"flags":    {"alpha": json.RawMessage(`{"key":"alpha","version":1,"rules":[{"id":"r1","clauses":[]}]}`), "beta": json.RawMessage(`{"key":"beta","version":1,"x":1.50}`)},
		"segments": {},
	}); err != nil {
		t.Fatal(err)
	}
	if err := second.replace(map[string]map[string]json.RawMessage{
		"segments": {},
		"flags":    {"beta": json.RawMessage(` { "x": 1.50, "version": 1, "key": "beta" } `)},
	}); err != nil {
		t.Fatal(err)
	}
	second.upsert("flags", "alpha", versionedItem{version: 1, raw: json.RawMessage(`{"rules":[{"clauses":[],"id":"r1"}],"version":1,"key":"alpha"}`)})

	a, err := first.snapshot()
	if err != nil {
		t.Fatal(err)
	}
	b, err := second.snapshot()
	if err != nil {
		t.Fatal(err)
	}
	if string(a) == string(b) {
		t.Fatal("the fixtures serialize identically, so this test cannot tell content comparison from byte comparison")
	}

	canonicalA, err := canonicalJSON(a)
	if err != nil {
		t.Fatal(err)
	}
	canonicalB, err := canonicalJSON(b)
	if err != nil {
		t.Fatal(err)
	}
	if string(canonicalA) != string(canonicalB) {
		t.Errorf("canonical forms differ for the same content:\n%s\n%s", canonicalA, canonicalB)
	}
	if !strings.Contains(string(canonicalA), `"x":1.50`) {
		t.Errorf("the number literal was not preserved: %s", canonicalA)
	}

	// A real change must still register.
	second.upsert("flags", "beta", versionedItem{version: 2, raw: json.RawMessage(`{"key":"beta","version":2,"x":1.50}`)})
	c, err := second.snapshot()
	if err != nil {
		t.Fatal(err)
	}
	canonicalC, err := canonicalJSON(c)
	if err != nil {
		t.Fatal(err)
	}
	if string(canonicalC) == string(canonicalA) {
		t.Error("a changed version produced the same canonical form")
	}
}
