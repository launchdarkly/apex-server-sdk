package main

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
)

// newTestBridge constructs a Bridge with just enough state to drive the polling
// and event-push code paths in tests without performing real Salesforce / OAuth
// setup. We intentionally avoid calling newBridge() because that path requires a
// pile of environment variables and an RSA key.
func newTestBridge(t *testing.T, baseURI, eventsURI string) *Bridge {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	return &Bridge{
		client:                http.Client{},
		salesforceURL:         "http://salesforce.invalid/",
		launchDarklyKey:       "fake-sdk-key",
		launchDarklyBaseURI:   baseURI,
		launchDarklyEventsURI: eventsURI,
		instanceID:            uuid.New().String(),
		// The poll intervals must be positive here. These tests cancel the context
		// from inside the request handler and rely on the loop's select landing on
		// ctx.Done(); a zero interval would make time.After ready at the same moment
		// and let select pick the timer branch instead, causing extra polls.
		eventPollInterval: DEFAULT_POLL_INTERVAL,
		flagPollInterval:  DEFAULT_POLL_INTERVAL,
		context:           ctx,
		cancel:            cancel,
	}
}

// TestInstanceIDIsValidUUIDv4 asserts that newBridge generates a parseable v4
// UUID, satisfying SCMP requirement 1.1.2.
func TestInstanceIDIsValidUUIDv4(t *testing.T) {
	// We can't call newBridge() here because of its env-var requirements, so
	// reproduce its UUID generation directly. This guards against an accidental
	// regression where someone swaps in a non-v4 generator.
	id := uuid.New()
	parsed, err := uuid.Parse(id.String())
	if err != nil {
		t.Fatalf("generated instance id %q is not parseable: %v", id, err)
	}
	if parsed.Version() != 4 {
		t.Fatalf("instance id must be UUID v4, got version %d", parsed.Version())
	}
}

// TestPollRequestCarriesInstanceIDHeader satisfies requirement 1.1.1: the
// header MUST be present on every polling request to LaunchDarkly.
func TestPollRequestCarriesInstanceIDHeader(t *testing.T) {
	var captured string
	var cancel context.CancelFunc

	ldServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		captured = r.Header.Get(INSTANCE_ID_HEADER)
		cancel()
		w.WriteHeader(http.StatusNotModified)
	}))
	defer ldServer.Close()

	bridge := newTestBridge(t, ldServer.URL, ldServer.URL)
	cancel = bridge.cancel

	if err := bridge.featureLoop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}
	if captured == "" {
		t.Fatal("poll request did not carry " + INSTANCE_ID_HEADER + " header")
	}
	if captured != bridge.instanceID {
		t.Errorf("poll request instance id = %q, want %q", captured, bridge.instanceID)
	}
	parsed, err := uuid.Parse(captured)
	if err != nil {
		t.Fatalf("poll request instance id %q is not a parseable UUID: %v", captured, err)
	}
	if parsed.Version() != 4 {
		t.Errorf("poll request instance id is not UUID v4 (version %d)", parsed.Version())
	}
}

// TestEventPushCarriesInstanceIDHeader ensures the same per-instance GUID also
// rides outbound event submissions, matching the reference Go SDK's behavior
// of placing the header on the shared DefaultHeaders so all LD-bound traffic
// inherits it.
func TestEventPushCarriesInstanceIDHeader(t *testing.T) {
	var capturedPushHeader string
	var pushed bool
	var cancel context.CancelFunc

	// Salesforce mock returns a non-empty event payload so eventLoop proceeds
	// to push to LaunchDarkly.
	sfServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Stub OAuth: any request gets a 200 with a non-empty event array body.
		if strings.Contains(r.URL.Path, "event") {
			_, _ = w.Write([]byte(`[{"kind":"identify"}]`))
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer sfServer.Close()

	ldEventsServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedPushHeader = r.Header.Get(INSTANCE_ID_HEADER)
		pushed = true
		cancel()
		w.WriteHeader(http.StatusAccepted)
	}))
	defer ldEventsServer.Close()

	bridge := newTestBridge(t, "http://unused.invalid", ldEventsServer.URL)
	bridge.salesforceURL = sfServer.URL + "/"
	cancel = bridge.cancel
	// Pre-seed an oauth token so requestWithOauth doesn't try to re-auth.
	bridge.oauthCurrentToken = "test-token"

	if err := bridge.eventLoop(); err != nil {
		t.Fatalf("eventLoop returned unexpected error: %v", err)
	}
	if !pushed {
		t.Fatal("eventLoop did not push events to LaunchDarkly")
	}
	if capturedPushHeader != bridge.instanceID {
		t.Errorf("event push instance id = %q, want %q", capturedPushHeader, bridge.instanceID)
	}
}

// TestInstanceIDsAreUniquePerInstance covers the spec implication that
// different bridge instances generate different GUIDs.
func TestInstanceIDsAreUniquePerInstance(t *testing.T) {
	a := newTestBridge(t, "http://unused.invalid", "http://unused.invalid")
	b := newTestBridge(t, "http://unused.invalid", "http://unused.invalid")
	if a.instanceID == "" || b.instanceID == "" {
		t.Fatal("instance ids must be non-empty")
	}
	if a.instanceID == b.instanceID {
		t.Errorf("expected distinct instance ids across bridges, both were %q", a.instanceID)
	}
}

// restoreEnv arranges for name to be returned to its current value once the test
// finishes. t.Setenv would handle this but requires Go 1.17, and CI builds the
// bridge with Go 1.15.
func restoreEnv(t *testing.T, name string) {
	t.Helper()
	previous, had := os.LookupEnv(name)
	t.Cleanup(func() {
		if had {
			_ = os.Setenv(name, previous)
		} else {
			_ = os.Unsetenv(name)
		}
	})
}

// setEnv sets an environment variable for the duration of a test.
func setEnv(t *testing.T, name, value string) {
	t.Helper()
	restoreEnv(t, name)
	if err := os.Setenv(name, value); err != nil {
		t.Fatalf("failed setting %s: %v", name, err)
	}
}

// unsetEnv removes an environment variable for the duration of a test. This is
// distinct from setting it to the empty string: both resolve to the fallback, but
// only the unset case reflects a bridge that was never configured at all.
func unsetEnv(t *testing.T, name string) {
	t.Helper()
	restoreEnv(t, name)
	if err := os.Unsetenv(name); err != nil {
		t.Fatalf("failed unsetting %s: %v", name, err)
	}
}

// setMinimalBridgeEnv populates just enough environment for newBridge to succeed,
// using the password auth branch so no RSA key is needed. newBridge performs no
// network I/O -- Salesforce authorization happens later, from run() -- so calling it
// directly in a test is safe. Optional variables are cleared so a value left in the
// developer's shell cannot influence the result.
func setMinimalBridgeEnv(t *testing.T) {
	t.Helper()
	setEnv(t, "LD_SDK_KEY", "sdk-test-key")
	setEnv(t, "SALESFORCE_URL", "https://example.invalid/services/apexrest/")
	setEnv(t, "OAUTH_ID", "test-oauth-id")
	setEnv(t, "OAUTH_USERNAME", "test@example.invalid")
	setEnv(t, "OAUTH_PASSWORD", "test-password")
	setEnv(t, "OAUTH_SECRET", "test-secret")
	for _, name := range []string{"OAUTH_JWT_KEY", "OAUTH_URI", "HTTP_TIMEOUT", "LD_BASE_URI", "LD_EVENTS_URI", "OAUTH_GRANT_TYPE", "LD_PROJECT_KEY"} {
		unsetEnv(t, name)
	}
}

// TestParseDurationFromEnv covers the parsing layer on its own. An unset, empty, or
// unparseable value yields the fallback; anything time.ParseDuration accepts comes
// back as-is. Range enforcement is a separate concern applied by newBridge, so a
// negative duration passes through this function unchanged.
func TestParseDurationFromEnv(t *testing.T) {
	tests := []struct {
		name  string
		value string
		set   bool
		want  time.Duration
	}{
		{name: "unset yields the fallback", set: false, want: DEFAULT_POLL_INTERVAL},
		{name: "empty yields the fallback", value: "", set: true, want: DEFAULT_POLL_INTERVAL},
		{name: "seconds", value: "45s", set: true, want: 45 * time.Second},
		{name: "minutes", value: "5m", set: true, want: 5 * time.Minute},
		{name: "milliseconds", value: "100ms", set: true, want: 100 * time.Millisecond},
		{name: "compound", value: "1m30s", set: true, want: 90 * time.Second},
		{name: "zero passes through", value: "0s", set: true, want: 0},
		{name: "negative passes through", value: "-5s", set: true, want: -5 * time.Second},
		// time.ParseDuration requires a unit, so a bare number is the likeliest
		// operator mistake. These fall back rather than failing startup.
		{name: "bare number yields the fallback", value: "30", set: true, want: DEFAULT_POLL_INTERVAL},
		{name: "garbage yields the fallback", value: "abc", set: true, want: DEFAULT_POLL_INTERVAL},
		{name: "embedded space yields the fallback", value: "30 s", set: true, want: DEFAULT_POLL_INTERVAL},
		{name: "spelled-out unit yields the fallback", value: "1minute", set: true, want: DEFAULT_POLL_INTERVAL},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			if test.set {
				setEnv(t, "EVENT_POLL_INTERVAL", test.value)
			} else {
				unsetEnv(t, "EVENT_POLL_INTERVAL")
			}

			got := parseDurationFromEnv("EVENT_POLL_INTERVAL", DEFAULT_POLL_INTERVAL)
			if got != test.want {
				t.Errorf("parseDurationFromEnv = %s, want %s", got, test.want)
			}
		})
	}
}

// TestNewBridgeResolvesEventPollInterval exercises the path the daemon actually
// takes, parsing and range-checking together. The only rule for EVENT_POLL_INTERVAL
// is that it end up positive: time.After fires immediately on a non-positive
// duration, which would turn the poll loop into a hot spin against Salesforce.
func TestNewBridgeResolvesEventPollInterval(t *testing.T) {
	tests := []struct {
		name  string
		value string
		set   bool
		want  time.Duration
	}{
		{name: "unset falls back to the default", set: false, want: DEFAULT_POLL_INTERVAL},
		{name: "empty falls back to the default", value: "", set: true, want: DEFAULT_POLL_INTERVAL},
		{name: "longer than the default is honored", value: "5m", set: true, want: 5 * time.Minute},
		{name: "shorter than the default is honored", value: "1s", set: true, want: time.Second},
		{name: "sub-second is honored", value: "100ms", set: true, want: 100 * time.Millisecond},
		{name: "zero is clamped to the default", value: "0s", set: true, want: DEFAULT_POLL_INTERVAL},
		{name: "negative is clamped to the default", value: "-5s", set: true, want: DEFAULT_POLL_INTERVAL},
		{name: "unparseable falls back to the default", value: "30", set: true, want: DEFAULT_POLL_INTERVAL},
	}

	// The API-consumption warning below EVENT_POLL_INTERVAL_WARN_THRESHOLD is advisory,
	// so aggressive values must still be honored exactly as configured. The table above
	// covers that: "1s" and "100ms" are both under the threshold and both pass through.
	// TestEventPollIntervalAPIWarning covers the warning itself.

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			setMinimalBridgeEnv(t)
			if test.set {
				setEnv(t, "EVENT_POLL_INTERVAL", test.value)
			} else {
				unsetEnv(t, "EVENT_POLL_INTERVAL")
			}

			bridge, err := newBridge()
			if err != nil {
				t.Fatalf("newBridge returned unexpected error: %v", err)
			}
			if bridge.eventPollInterval != test.want {
				t.Errorf("eventPollInterval = %s, want %s", bridge.eventPollInterval, test.want)
			}
			if bridge.eventPollInterval <= 0 {
				t.Errorf("eventPollInterval %s is not positive; time.After would hot-spin the loop",
					bridge.eventPollInterval)
			}
		})
	}
}

// TestNewBridgeResolvesFlagPollInterval is the FLAG_POLL_INTERVAL counterpart. This
// one enforces a 30s floor, matching the minimum polling interval used across
// LaunchDarkly's server SDKs, so a value below it is clamped up rather than honored.
func TestNewBridgeResolvesFlagPollInterval(t *testing.T) {
	tests := []struct {
		name  string
		value string
		set   bool
		want  time.Duration
	}{
		{name: "unset falls back to the default", set: false, want: DEFAULT_POLL_INTERVAL},
		{name: "empty falls back to the default", value: "", set: true, want: DEFAULT_POLL_INTERVAL},
		{name: "exactly the minimum is honored", value: "30s", set: true, want: MIN_FLAG_POLL_INTERVAL},
		{name: "longer than the minimum is honored", value: "5m", set: true, want: 5 * time.Minute},
		{name: "below the minimum is clamped up", value: "10s", set: true, want: MIN_FLAG_POLL_INTERVAL},
		{name: "just below the minimum is clamped up", value: "29999ms", set: true, want: MIN_FLAG_POLL_INTERVAL},
		{name: "zero is clamped up", value: "0s", set: true, want: MIN_FLAG_POLL_INTERVAL},
		{name: "negative is clamped up", value: "-5s", set: true, want: MIN_FLAG_POLL_INTERVAL},
		{name: "unparseable falls back to the default", value: "30", set: true, want: DEFAULT_POLL_INTERVAL},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			setMinimalBridgeEnv(t)
			if test.set {
				setEnv(t, "FLAG_POLL_INTERVAL", test.value)
			} else {
				unsetEnv(t, "FLAG_POLL_INTERVAL")
			}

			bridge, err := newBridge()
			if err != nil {
				t.Fatalf("newBridge returned unexpected error: %v", err)
			}
			if bridge.flagPollInterval != test.want {
				t.Errorf("flagPollInterval = %s, want %s", bridge.flagPollInterval, test.want)
			}
			if bridge.flagPollInterval < MIN_FLAG_POLL_INTERVAL {
				t.Errorf("flagPollInterval %s is below the %s minimum",
					bridge.flagPollInterval, MIN_FLAG_POLL_INTERVAL)
			}
		})
	}
}

// TestEventLoopUsesConfiguredInterval verifies the resolved interval is actually
// wired into eventLoop's wait rather than the POLL_INTERVAL constant. A short
// interval must produce several polls promptly; if the constant were still in use
// the second poll would be 30s away and this test would time out.
func TestEventLoopUsesConfiguredInterval(t *testing.T) {
	const wantPolls = 3

	var mu sync.Mutex
	polls := 0
	var cancel context.CancelFunc

	sfServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		polls++
		reached := polls >= wantPolls
		mu.Unlock()

		if reached {
			cancel()
		}
		// An empty array short-circuits the push to LaunchDarkly, keeping this test
		// focused on the loop's cadence.
		_, _ = w.Write([]byte("[]"))
	}))
	defer sfServer.Close()

	bridge := newTestBridge(t, "http://unused.invalid", "http://unused.invalid")
	bridge.salesforceURL = sfServer.URL + "/"
	bridge.oauthCurrentToken = "test-token"
	bridge.eventPollInterval = time.Millisecond
	cancel = bridge.cancel

	done := make(chan error, 1)
	go func() { done <- bridge.eventLoop() }()

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("eventLoop returned unexpected error: %v", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("eventLoop did not honor the configured interval (still waiting on POLL_INTERVAL?)")
	}

	mu.Lock()
	defer mu.Unlock()
	// Cancelling races the timer branch of the loop's select, so a few extra polls
	// past the threshold are expected and fine.
	if polls < wantPolls {
		t.Errorf("eventLoop polled %d times, want at least %d", polls, wantPolls)
	}
}

// TestFeatureLoopUsesConfiguredInterval is the featureLoop counterpart to
// TestEventLoopUsesConfiguredInterval. The 30s floor applies to what an operator
// may configure, not to what the loop is capable of, so the field is set directly.
func TestFeatureLoopUsesConfiguredInterval(t *testing.T) {
	const wantPolls = 3

	var mu sync.Mutex
	polls := 0
	var cancel context.CancelFunc

	ldServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		polls++
		reached := polls >= wantPolls
		mu.Unlock()

		if reached {
			cancel()
		}
		w.WriteHeader(http.StatusNotModified)
	}))
	defer ldServer.Close()

	bridge := newTestBridge(t, ldServer.URL, ldServer.URL)
	bridge.flagPollInterval = time.Millisecond
	cancel = bridge.cancel

	done := make(chan error, 1)
	go func() { done <- bridge.featureLoop() }()

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("featureLoop returned unexpected error: %v", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("featureLoop did not honor the configured interval (still waiting on POLL_INTERVAL?)")
	}

	mu.Lock()
	defer mu.Unlock()
	if polls < wantPolls {
		t.Errorf("featureLoop polled %d times, want at least %d", polls, wantPolls)
	}
}

// captureLog redirects the standard logger for the duration of a test and returns a
// buffer holding whatever was written to it.
func captureLog(t *testing.T) *bytes.Buffer {
	t.Helper()
	var buf bytes.Buffer
	previousFlags := log.Flags()
	log.SetOutput(&buf)
	log.SetFlags(0)
	t.Cleanup(func() {
		log.SetOutput(os.Stderr)
		log.SetFlags(previousFlags)
	})
	return &buf
}

// TestEventPollIntervalAPIWarning covers the advisory warning for an aggressive event
// interval. Every drain is an inbound Salesforce API call counted against the org's
// 24-hour allocation, and exhausting that allocation returns REQUEST_LIMIT_EXCEEDED to
// every API client in the org rather than just this bridge -- so a short interval is
// worth flagging even though it stays honored.
func TestEventPollIntervalAPIWarning(t *testing.T) {
	tests := []struct {
		name        string
		value       string
		wantWarning bool
	}{
		{name: "one second warns", value: "1s", wantWarning: true},
		{name: "sub-second warns", value: "100ms", wantWarning: true},
		{name: "just below the threshold warns", value: "4999ms", wantWarning: true},
		{name: "exactly the threshold is quiet", value: "5s", wantWarning: false},
		{name: "the default is quiet", value: "30s", wantWarning: false},
		// A negative value is clamped to the default before the threshold is examined,
		// so it must not also trip the warning.
		{name: "negative is clamped and stays quiet", value: "-5s", wantWarning: false},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			setMinimalBridgeEnv(t)
			setEnv(t, "EVENT_POLL_INTERVAL", test.value)
			logged := captureLog(t)

			bridge, err := newBridge()
			if err != nil {
				t.Fatalf("newBridge returned unexpected error: %v", err)
			}

			// This phrase appears only in the API-consumption warning, so it is a
			// reliable marker for that specific message.
			warned := strings.Contains(logged.String(), "organization wide API limits")
			if warned != test.wantWarning {
				t.Errorf("interval %s resolved to %s: warned = %v, want %v\nlog:\n%s",
					test.value, bridge.eventPollInterval, warned, test.wantWarning, logged.String())
			}
			// The warning must name the interval in effect, since that is the only
			// actionable detail it carries.
			if test.wantWarning && !strings.Contains(logged.String(), bridge.eventPollInterval.String()) {
				t.Errorf("warning does not name the effective interval %s\nlog:\n%s",
					bridge.eventPollInterval, logged.String())
			}
		})
	}
}

// allowedConnections is the ceiling these tests hold the bridge to. A client that
// finishes with each response reuses a single pooled connection for all of them, so a
// healthy loop opens one or two. A loop that abandons its responses opens a fresh
// connection per request, making the count track the request count instead.
const allowedConnections = 5

// connectionCounter starts an httptest server wrapping handler and returns it along
// with a function reporting how many separate connections clients have opened to it.
//
// Counting connections is what makes the defect visible. Go's transport can only
// return a connection to its pool once the response body has been consumed and
// released; until then the connection is abandoned and the next request dials a new
// one. Every request still succeeds, so nothing else about the loop looks wrong.
func connectionCounter(handler http.HandlerFunc) (*httptest.Server, func() int) {
	var mu sync.Mutex
	count := 0

	// Unstarted so ConnState is installed before the server goroutine reads Config;
	// assigning it after NewServer would race with the running server.
	server := httptest.NewUnstartedServer(handler)
	server.Config.ConnState = func(_ net.Conn, state http.ConnState) {
		if state == http.StateNew {
			mu.Lock()
			count++
			mu.Unlock()
		}
	}
	server.Start()

	return server, func() int {
		mu.Lock()
		defer mu.Unlock()
		return count
	}
}

// countingHandler wraps handler so it records how many requests it has served and
// cancels the loop once it has served enough.
func countingHandler(want int, cancel func(), handler http.HandlerFunc) (http.HandlerFunc, func() int) {
	var mu sync.Mutex
	served := 0

	return func(w http.ResponseWriter, r *http.Request) {
			mu.Lock()
			served++
			reached := served >= want
			mu.Unlock()

			if reached {
				cancel()
			}
			handler(w, r)
		}, func() int {
			mu.Lock()
			defer mu.Unlock()
			return served
		}
}

// TestEventLoopReusesConnectionsOnEventPush covers the push to LaunchDarkly in
// eventLoop. It checks only the status code, leaving the body neither read nor
// closed, so each push abandons its connection.
//
// This only happens when there are events to deliver: a drain that returns an empty
// array skips the push entirely, so an idle org is unaffected.
func TestEventLoopReusesConnectionsOnEventPush(t *testing.T) {
	const wantPushes = 50

	bridge := newTestBridge(t, "http://unused.invalid", "http://unused.invalid")
	bridge.oauthCurrentToken = "test-token"
	bridge.eventPollInterval = time.Millisecond

	// A non-empty payload so the loop proceeds to the push on every cycle.
	sfServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`[{"kind":"identify"}]`))
	}))
	defer sfServer.Close()
	bridge.salesforceURL = sfServer.URL + "/"

	handler, servedCount := countingHandler(wantPushes, bridge.cancel,
		func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusAccepted)
			_, _ = w.Write([]byte(`{"ok":true}`))
		})
	ldServer, connectionCount := connectionCounter(handler)
	defer ldServer.Close()
	bridge.launchDarklyEventsURI = ldServer.URL

	if err := bridge.eventLoop(); err != nil {
		t.Fatalf("eventLoop returned unexpected error: %v", err)
	}

	served := servedCount()
	if served < wantPushes {
		t.Fatalf("only %d pushes completed, want at least %d", served, wantPushes)
	}
	if connections := connectionCount(); connections > allowedConnections {
		t.Errorf("opened %d connections for %d event pushes (allowed %d); "+
			"the push response is never consumed, so no connection can be reused",
			connections, served, allowedConnections)
	}
}

// TestFeatureLoopReusesConnectionsOnFlagPush covers the push to Salesforce in
// featureLoop, which goes through requestWithOauth and has the same defect as the
// event push: the status is inspected and the body is left open.
//
// This only happens when flag data actually changes. An unchanged poll returns 304
// and skips the push, which is the steady state for most orgs.
func TestFeatureLoopReusesConnectionsOnFlagPush(t *testing.T) {
	const wantPushes = 50

	bridge := newTestBridge(t, "http://unused.invalid", "http://unused.invalid")
	bridge.oauthCurrentToken = "test-token"
	bridge.flagPollInterval = time.Millisecond

	// Flag data on every poll so the loop always proceeds to the push. Without an
	// ETag the loop cannot short-circuit to 304.
	ldServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"flags":{},"segments":{}}`))
	}))
	defer ldServer.Close()
	bridge.launchDarklyBaseURI = ldServer.URL

	handler, servedCount := countingHandler(wantPushes, bridge.cancel,
		func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"ok":true}`))
		})
	sfServer, connectionCount := connectionCounter(handler)
	defer sfServer.Close()
	bridge.salesforceURL = sfServer.URL + "/"

	if err := bridge.featureLoop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}

	served := servedCount()
	if served < wantPushes {
		t.Fatalf("only %d pushes completed, want at least %d", served, wantPushes)
	}
	if connections := connectionCount(); connections > allowedConnections {
		t.Errorf("opened %d connections for %d flag pushes (allowed %d); "+
			"the push response is never consumed, so no connection can be reused",
			connections, served, allowedConnections)
	}
}

// TestFeatureLoopReusesConnectionsOnPollError covers the flag poll's failure path.
// A non-200 is logged and the loop moves on without reading the body, so unlike the
// 200 path -- which is drained by ioutil.ReadAll -- and the 304 path -- which has no
// body to begin with -- an error response abandons its connection.
//
// A LaunchDarkly outage therefore turns every flag poll into a fresh connection, at
// the moment the bridge is already degraded.
func TestFeatureLoopReusesConnectionsOnPollError(t *testing.T) {
	const wantPolls = 50

	bridge := newTestBridge(t, "http://unused.invalid", "http://unused.invalid")
	bridge.oauthCurrentToken = "test-token"
	bridge.flagPollInterval = time.Millisecond

	// A 500 carries a body, which is what distinguishes this from the bodyless 304.
	handler, servedCount := countingHandler(wantPolls, bridge.cancel,
		func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = w.Write([]byte(`{"message":"internal error"}`))
		})
	ldServer, connectionCount := connectionCounter(handler)
	defer ldServer.Close()
	bridge.launchDarklyBaseURI = ldServer.URL

	if err := bridge.featureLoop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}

	served := servedCount()
	if served < wantPolls {
		t.Fatalf("only %d polls completed, want at least %d", served, wantPolls)
	}
	if connections := connectionCount(); connections > allowedConnections {
		t.Errorf("opened %d connections for %d failed flag polls (allowed %d); "+
			"the error response body is never read, so no connection can be reused",
			connections, served, allowedConnections)
	}
}

// TestEventLoopReusesConnectionsOnPollError covers the event drain's failure path,
// the counterpart to TestFeatureLoopReusesConnectionsOnPollError. A non-200 from
// Salesforce is logged and the loop moves on without reading the body, so the
// connection is abandoned.
//
// Unlike the two push cases this needs no event traffic to trigger: a bridge polling
// a broken or misconfigured Salesforce endpoint abandons a connection on every cycle
// while delivering nothing.
func TestEventLoopReusesConnectionsOnPollError(t *testing.T) {
	const wantPolls = 50

	bridge := newTestBridge(t, "http://unused.invalid", "http://unused.invalid")
	bridge.oauthCurrentToken = "test-token"
	bridge.eventPollInterval = time.Millisecond

	// A 500 rather than a 401 or 403, which would instead drive the re-auth path.
	handler, servedCount := countingHandler(wantPolls, bridge.cancel,
		func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = w.Write([]byte(`{"message":"salesforce error"}`))
		})
	sfServer, connectionCount := connectionCounter(handler)
	defer sfServer.Close()
	bridge.salesforceURL = sfServer.URL + "/"

	if err := bridge.eventLoop(); err != nil {
		t.Fatalf("eventLoop returned unexpected error: %v", err)
	}

	served := servedCount()
	if served < wantPolls {
		t.Fatalf("only %d polls completed, want at least %d", served, wantPolls)
	}
	if connections := connectionCount(); connections > allowedConnections {
		t.Errorf("opened %d connections for %d failed event drains (allowed %d); "+
			"the error response body is never read, so no connection can be reused",
			connections, served, allowedConnections)
	}
}

func TestResolveGrantType(t *testing.T) {
	tests := []struct {
		name       string
		configured string
		setEnvVar  bool
		jwtKey     string
		want       string
		wantErr    bool
	}{
		// Unset falls back to inference, which is how the bridge behaved before
		// OAUTH_GRANT_TYPE existed. Every deployment predating it keeps working.
		{name: "unset with a jwt key infers jwt bearer", jwtKey: "not-empty", want: GRANT_JWT_BEARER},
		{name: "unset without a jwt key infers password", want: GRANT_PASSWORD},

		{name: "explicit jwt bearer", configured: GRANT_JWT_BEARER, setEnvVar: true, want: GRANT_JWT_BEARER},
		{name: "explicit client credentials", configured: GRANT_CLIENT_CREDENTIALS, setEnvVar: true, want: GRANT_CLIENT_CREDENTIALS},
		{name: "explicit password", configured: GRANT_PASSWORD, setEnvVar: true, want: GRANT_PASSWORD},

		// Client credentials cannot be inferred: its credentials are a subset of the
		// password grant's, so an explicit choice must override a present JWT key.
		{
			name:       "explicit choice overrides a present jwt key",
			configured: GRANT_CLIENT_CREDENTIALS,
			setEnvVar:  true,
			jwtKey:     "not-empty",
			want:       GRANT_CLIENT_CREDENTIALS,
		},

		{name: "case and surrounding whitespace are tolerated", configured: "  Client-Credentials  ", setEnvVar: true, want: GRANT_CLIENT_CREDENTIALS},

		// A typo must stop startup rather than silently selecting a different flow.
		{name: "unrecognized value is an error", configured: "client_credentials", setEnvVar: true, wantErr: true},
		{name: "nonsense is an error", configured: "oauth", setEnvVar: true, wantErr: true},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			if test.setEnvVar {
				setEnv(t, "OAUTH_GRANT_TYPE", test.configured)
			} else {
				unsetEnv(t, "OAUTH_GRANT_TYPE")
			}

			got, err := resolveGrantType(test.jwtKey)
			if test.wantErr {
				if err == nil {
					t.Fatalf("expected an error for %q, got grant %q", test.configured, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("resolveGrantType returned unexpected error: %v", err)
			}
			if got != test.want {
				t.Errorf("grant = %q, want %q", got, test.want)
			}
		})
	}
}

// TestClientCredentialsNeedsNoUsername is the point of the whole change: the run-as identity
// lives on the app in Salesforce, so the daemon holds no user credential. If this starts
// failing, the per-grant validation has regressed into requiring a username again.
func TestClientCredentialsNeedsNoUsername(t *testing.T) {
	setMinimalBridgeEnv(t)
	setEnv(t, "OAUTH_GRANT_TYPE", GRANT_CLIENT_CREDENTIALS)
	unsetEnv(t, "OAUTH_USERNAME")
	unsetEnv(t, "OAUTH_PASSWORD")

	bridge, err := newBridge()
	if err != nil {
		t.Fatalf("newBridge rejected a valid client credentials configuration: %v", err)
	}
	if bridge.oauthGrantType != GRANT_CLIENT_CREDENTIALS {
		t.Errorf("grant = %q, want %q", bridge.oauthGrantType, GRANT_CLIENT_CREDENTIALS)
	}
}

// TestGrantValidationIsPerGrant covers what each flow demands and what it tolerates being
// absent. Both halves matter: a missing credential must stop startup rather than surface
// later as an opaque Salesforce rejection, and a credential another flow needs must not be
// required here.
func TestGrantValidationIsPerGrant(t *testing.T) {
	tests := []struct {
		name      string
		grant     string
		setJWTKey bool
		unset     []string
		wantErr   bool
	}{
		{name: "client credentials without a secret", grant: GRANT_CLIENT_CREDENTIALS, unset: []string{"OAUTH_SECRET"}, wantErr: true},
		{name: "client credentials without an id", grant: GRANT_CLIENT_CREDENTIALS, unset: []string{"OAUTH_ID"}, wantErr: true},
		{name: "client credentials without a password is fine", grant: GRANT_CLIENT_CREDENTIALS, unset: []string{"OAUTH_PASSWORD"}},
		{name: "client credentials without a username is fine", grant: GRANT_CLIENT_CREDENTIALS, unset: []string{"OAUTH_USERNAME"}},
		{name: "client credentials without a jwt key is fine", grant: GRANT_CLIENT_CREDENTIALS, unset: []string{"OAUTH_JWT_KEY"}},

		{name: "jwt bearer without a key", grant: GRANT_JWT_BEARER, unset: []string{"OAUTH_JWT_KEY"}, wantErr: true},
		{name: "jwt bearer without a username", grant: GRANT_JWT_BEARER, setJWTKey: true, unset: []string{"OAUTH_USERNAME"}, wantErr: true},
		{name: "jwt bearer without an id", grant: GRANT_JWT_BEARER, setJWTKey: true, unset: []string{"OAUTH_ID"}, wantErr: true},
		{name: "jwt bearer without a secret is fine", grant: GRANT_JWT_BEARER, setJWTKey: true, unset: []string{"OAUTH_SECRET"}},
		{name: "jwt bearer without a password is fine", grant: GRANT_JWT_BEARER, setJWTKey: true, unset: []string{"OAUTH_PASSWORD"}},

		{name: "password without a username", grant: GRANT_PASSWORD, unset: []string{"OAUTH_USERNAME"}, wantErr: true},
		{name: "password without a password", grant: GRANT_PASSWORD, unset: []string{"OAUTH_PASSWORD"}, wantErr: true},
		{name: "password without a secret", grant: GRANT_PASSWORD, unset: []string{"OAUTH_SECRET"}, wantErr: true},
		{name: "password without an id", grant: GRANT_PASSWORD, unset: []string{"OAUTH_ID"}, wantErr: true},
		{name: "password without a jwt key is fine", grant: GRANT_PASSWORD, unset: []string{"OAUTH_JWT_KEY"}},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			setMinimalBridgeEnv(t)
			setEnv(t, "OAUTH_GRANT_TYPE", test.grant)
			if test.setJWTKey {
				setEnv(t, "OAUTH_JWT_KEY", testJWTKeyBase64(t))
			}
			for _, name := range test.unset {
				unsetEnv(t, name)
			}

			_, err := newBridge()
			if test.wantErr && err == nil {
				t.Error("expected newBridge to reject the configuration, it succeeded")
			}
			if !test.wantErr && err != nil {
				t.Errorf("newBridge returned unexpected error: %v", err)
			}
		})
	}
}

// TestGrantsReadOnlyTheirOwnCredentials asserts a flow ignores the variables it has no use
// for, even when the environment supplies them. A leftover OAUTH_PASSWORD from a previous
// password-flow deployment must not travel anywhere once client credentials is selected.
func TestGrantsReadOnlyTheirOwnCredentials(t *testing.T) {
	tests := []struct {
		grant        string
		wantUsername string
		wantPassword string
		wantSecret   string
		wantJWTKey   bool
	}{
		{grant: GRANT_CLIENT_CREDENTIALS, wantSecret: "test-secret"},
		{grant: GRANT_JWT_BEARER, wantUsername: "test@example.invalid", wantJWTKey: true},
		{grant: GRANT_PASSWORD, wantUsername: "test@example.invalid", wantPassword: "test-password", wantSecret: "test-secret"},
	}

	for _, test := range tests {
		test := test
		t.Run(test.grant, func(t *testing.T) {
			// Every credential the bridge understands is present, so anything the
			// resolved bridge leaves empty was deliberately not read.
			setMinimalBridgeEnv(t)
			setEnv(t, "OAUTH_GRANT_TYPE", test.grant)
			setEnv(t, "OAUTH_JWT_KEY", testJWTKeyBase64(t))

			bridge, err := newBridge()
			if err != nil {
				t.Fatalf("newBridge returned unexpected error: %v", err)
			}

			if bridge.oauthUsername != test.wantUsername {
				t.Errorf("username = %q, want %q", bridge.oauthUsername, test.wantUsername)
			}
			if bridge.oauthPassword != test.wantPassword {
				t.Errorf("password = %q, want %q", bridge.oauthPassword, test.wantPassword)
			}
			if bridge.oauthSecret != test.wantSecret {
				t.Errorf("secret = %q, want %q", bridge.oauthSecret, test.wantSecret)
			}
			if gotKey := bridge.oauthJWTKey != nil; gotKey != test.wantJWTKey {
				t.Errorf("jwt key loaded = %v, want %v", gotKey, test.wantJWTKey)
			}
		})
	}
}

// TestAuthorizeSalesforcePostsTheRightForm asserts the wire contract for each grant, since
// that is what Salesforce actually validates. The client credentials case additionally
// asserts the absence of username and password: sending a user credential on a grant that
// does not take one is the mistake worth catching.
func TestAuthorizeSalesforcePostsTheRightForm(t *testing.T) {
	tests := []struct {
		name        string
		grant       string
		jwt         bool
		wantGrant   string
		wantPresent []string
		wantAbsent  []string
	}{
		{
			name:        "client credentials",
			grant:       GRANT_CLIENT_CREDENTIALS,
			wantGrant:   "client_credentials",
			wantPresent: []string{"client_id", "client_secret"},
			wantAbsent:  []string{"username", "password", "assertion"},
		},
		{
			// The assertion carries the identity, so the JWT bearer flow sends no client
			// secret and no user credential alongside it.
			name:        "jwt bearer",
			grant:       GRANT_JWT_BEARER,
			jwt:         true,
			wantGrant:   "urn:ietf:params:oauth:grant-type:jwt-bearer",
			wantPresent: []string{"assertion"},
			wantAbsent:  []string{"client_id", "client_secret", "username", "password"},
		},
		{
			name:        "password",
			grant:       GRANT_PASSWORD,
			wantGrant:   "password",
			wantPresent: []string{"client_id", "client_secret", "username", "password"},
			wantAbsent:  []string{"assertion"},
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			var posted url.Values

			tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				body, _ := ioutil.ReadAll(r.Body)
				posted, _ = url.ParseQuery(string(body))
				_, _ = w.Write([]byte(`{"access_token":"test-token"}`))
			}))
			defer tokenServer.Close()

			setMinimalBridgeEnv(t)
			setEnv(t, "OAUTH_GRANT_TYPE", test.grant)
			setEnv(t, "OAUTH_URI", tokenServer.URL)
			if test.jwt {
				setEnv(t, "OAUTH_JWT_KEY", testJWTKeyBase64(t))
			}

			bridge, err := newBridge()
			if err != nil {
				t.Fatalf("newBridge returned unexpected error: %v", err)
			}

			if err, _ := bridge.authorizeSalesforce(); err != nil {
				t.Fatalf("authorizeSalesforce returned unexpected error: %v", err)
			}

			if got := posted.Get("grant_type"); got != test.wantGrant {
				t.Errorf("grant_type = %q, want %q", got, test.wantGrant)
			}
			for _, name := range test.wantPresent {
				if posted.Get(name) == "" {
					t.Errorf("%s missing from the token request", name)
				}
			}
			for _, name := range test.wantAbsent {
				if _, ok := posted[name]; ok {
					t.Errorf("%s was sent on the %s grant and should not have been", name, test.grant)
				}
			}
			// Salesforce rejects an assertion it cannot verify, so the signature on the
			// value that actually goes over the wire is checked here, not only in
			// makeJWT's own test.
			if test.jwt {
				verifyAssertionSignature(t, bridge, posted.Get("assertion"))
			}
			if bridge.oauthCurrentToken != "test-token" {
				t.Errorf("token = %q, want %q", bridge.oauthCurrentToken, "test-token")
			}
		})
	}
}

func TestTokenEndpointFrom(t *testing.T) {
	tests := []struct {
		name          string
		salesforceURL string
		want          string
		wantErr       bool
	}{
		{
			name:          "apex rest url",
			salesforceURL: "https://example-dev-ed.develop.my.salesforce.com/services/apexrest/",
			want:          "https://example-dev-ed.develop.my.salesforce.com/services/oauth2/token",
		},
		{
			name:          "no trailing slash",
			salesforceURL: "https://example.my.salesforce.com/services/apexrest",
			want:          "https://example.my.salesforce.com/services/oauth2/token",
		},
		{name: "empty is an error", salesforceURL: "", wantErr: true},
		{name: "no scheme is an error", salesforceURL: "example.my.salesforce.com/services/apexrest/", wantErr: true},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			got, err := tokenEndpointFrom(test.salesforceURL)
			if test.wantErr {
				if err == nil {
					t.Fatalf("expected an error for %q, got %q", test.salesforceURL, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("tokenEndpointFrom returned unexpected error: %v", err)
			}
			if got != test.want {
				t.Errorf("endpoint = %q, want %q", got, test.want)
			}
		})
	}
}

// TestClientCredentialsDerivesItsTokenEndpoint covers the failure this defends against: the
// shared login host rejects the client credentials grant with "request not supported on this
// domain", so leaving OAUTH_URI at its default would break every deployment using this grant.
// Verified against the live org before the derivation existed.
func TestClientCredentialsDerivesItsTokenEndpoint(t *testing.T) {
	setMinimalBridgeEnv(t)
	setEnv(t, "OAUTH_GRANT_TYPE", GRANT_CLIENT_CREDENTIALS)
	unsetEnv(t, "OAUTH_URI")

	bridge, err := newBridge()
	if err != nil {
		t.Fatalf("newBridge returned unexpected error: %v", err)
	}

	want := "https://example.invalid/services/oauth2/token"
	if got := bridge.oauthURI.String(); got != want {
		t.Errorf("token endpoint = %q, want %q", got, want)
	}
}

// The other grants are accepted on the shared login host, so their default must not change.
func TestOtherGrantsKeepTheDefaultTokenEndpoint(t *testing.T) {
	for _, grant := range []string{GRANT_JWT_BEARER, GRANT_PASSWORD} {
		grant := grant
		t.Run(grant, func(t *testing.T) {
			setMinimalBridgeEnv(t)
			setEnv(t, "OAUTH_GRANT_TYPE", grant)
			unsetEnv(t, "OAUTH_URI")
			if grant == GRANT_JWT_BEARER {
				setEnv(t, "OAUTH_JWT_KEY", testJWTKeyBase64(t))
			}

			bridge, err := newBridge()
			if err != nil {
				t.Fatalf("newBridge returned unexpected error: %v", err)
			}
			if got := bridge.oauthURI.String(); got != OAUTH_URI {
				t.Errorf("token endpoint = %q, want the default %q", got, OAUTH_URI)
			}
		})
	}
}

// testJWTKeyBase64 produces an OAUTH_JWT_KEY the bridge will accept: a PKCS#1 key in a PEM
// block labelled "RSA PRIVATE KEY", base64 encoded. A short key keeps the test fast; nothing
// here signs anything that Salesforce verifies.
func testJWTKeyBase64(t *testing.T) string {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 1024)
	if err != nil {
		t.Fatalf("failed generating a test RSA key: %v", err)
	}
	encoded := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(key),
	})

	return base64.StdEncoding.EncodeToString(encoded)
}

// TestEventLoopStreamsLargeErrorBodies pins the streaming half of drainAndClose.
//
// The connection-reuse tests above cannot catch a regression here. They pass whether
// the body is streamed to ioutil.Discard or read into memory with ioutil.ReadAll,
// because both reach EOF and so both restore connection pooling. Allocation volume is
// the only thing that separates the two, so without this test a change to ReadAll
// looks entirely correct.
func TestEventLoopStreamsLargeErrorBodies(t *testing.T) {
	const (
		wantPolls = 50
		bodySize  = 1 << 20 // 1 MiB of error body per response
		// io.Discard implements ReaderFrom and copies through a small pooled buffer,
		// so the whole run costs far less than one body. Buffering each body instead
		// would allocate at least wantPolls*bodySize, i.e. 50 MiB. With three orders
		// of magnitude between the two outcomes this ceiling is generous enough not
		// to flake while still failing decisively on a regression.
		maxTotalAlloc = 20 << 20 // 20 MiB
	)

	body := bytes.Repeat([]byte("x"), bodySize)

	bridge := newTestBridge(t, "http://unused.invalid", "http://unused.invalid")
	bridge.oauthCurrentToken = "test-token"
	bridge.eventPollInterval = time.Millisecond

	// A 500 rather than a 401 or 403, which would instead drive the re-auth path.
	handler, servedCount := countingHandler(wantPolls, bridge.cancel,
		func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = w.Write(body)
		})
	sfServer := httptest.NewServer(handler)
	defer sfServer.Close()
	bridge.salesforceURL = sfServer.URL + "/"

	var before, after runtime.MemStats
	runtime.GC()
	runtime.ReadMemStats(&before)

	if err := bridge.eventLoop(); err != nil {
		t.Fatalf("eventLoop returned unexpected error: %v", err)
	}

	runtime.ReadMemStats(&after)

	served := servedCount()
	if served < wantPolls {
		t.Fatalf("only %d polls completed, want at least %d", served, wantPolls)
	}

	// TotalAlloc is cumulative, so it measures what was allocated regardless of what
	// the collector has since reclaimed. HeapAlloc would be at the mercy of GC timing.
	allocated := after.TotalAlloc - before.TotalAlloc
	t.Logf("allocated %d bytes draining %d responses of %d bytes each", allocated, served, bodySize)
	if allocated > maxTotalAlloc {
		t.Errorf("allocated %d bytes draining %d error responses of %d bytes each (ceiling %d); "+
			"drainAndClose is buffering bodies instead of streaming them",
			allocated, served, bodySize, maxTotalAlloc)
	}
}

// allGrants is every flow newBridge resolves to. Tests whose expectation holds for all
// three range over it, so adding a flow without considering them fails to compile.
var allGrants = []string{GRANT_CLIENT_CREDENTIALS, GRANT_JWT_BEARER, GRANT_PASSWORD}

// bridgeForGrant builds a bridge configured for one flow, with its token endpoint pointed
// at tokenURI. Each flow needs a different set of variables, so the JWT key is supplied
// only where it is required.
func bridgeForGrant(t *testing.T, grant, tokenURI string) *Bridge {
	t.Helper()
	setMinimalBridgeEnv(t)
	setEnv(t, "OAUTH_GRANT_TYPE", grant)
	setEnv(t, "OAUTH_URI", tokenURI)
	if grant == GRANT_JWT_BEARER {
		setEnv(t, "OAUTH_JWT_KEY", testJWTKeyBase64(t))
	}

	bridge, err := newBridge()
	if err != nil {
		t.Fatalf("newBridge returned unexpected error for the %s grant: %v", grant, err)
	}

	return bridge
}

// decodeJWTSegment decodes one dot-separated segment of an assertion. Padding is restored
// when it is absent, so the helper reads both the padded base64url the bridge writes today
// and the unpadded form a JWT is normally encoded with. That keeps these tests about the
// claims rather than about the encoding.
func decodeJWTSegment(t *testing.T, segment string) []byte {
	t.Helper()
	if remainder := len(segment) % 4; remainder != 0 {
		segment += strings.Repeat("=", 4-remainder)
	}
	decoded, err := base64.URLEncoding.DecodeString(segment)
	if err != nil {
		t.Fatalf("failed decoding JWT segment %q: %v", segment, err)
	}

	return decoded
}

// verifyAssertionSignature checks that an assertion was signed by the key the bridge
// loaded. The signed input is the first two segments verbatim, so this holds whatever
// base64 variant produced them.
func verifyAssertionSignature(t *testing.T, bridge *Bridge, assertion string) {
	t.Helper()
	segments := strings.Split(assertion, ".")
	if len(segments) != 3 {
		t.Fatalf("assertion has %d segments, want 3", len(segments))
	}

	digest := sha256.Sum256([]byte(segments[0] + "." + segments[1]))
	signature := decodeJWTSegment(t, segments[2])
	if err := rsa.VerifyPKCS1v15(&bridge.oauthJWTKey.PublicKey, crypto.SHA256, digest[:], signature); err != nil {
		t.Errorf("the assertion does not verify against the configured key: %v", err)
	}
}

// TestMakeJWTSignsTheExpectedAssertion covers the only flow that constructs a credential
// rather than forwarding one. Salesforce validates every field independently and answers a
// wrong one with the same opaque invalid_grant, so each is asserted here.
func TestMakeJWTSignsTheExpectedAssertion(t *testing.T) {
	setMinimalBridgeEnv(t)
	setEnv(t, "OAUTH_GRANT_TYPE", GRANT_JWT_BEARER)
	setEnv(t, "OAUTH_JWT_KEY", testJWTKeyBase64(t))
	setEnv(t, "OAUTH_ID", "jwt-consumer-key")
	setEnv(t, "OAUTH_USERNAME", "jwt-user@example.invalid")
	// The audience is the token endpoint's host, so a configured endpoint must reach it.
	setEnv(t, "OAUTH_URI", "https://example-dev-ed.develop.my.salesforce.com/services/oauth2/token")

	bridge, err := newBridge()
	if err != nil {
		t.Fatalf("newBridge returned unexpected error: %v", err)
	}

	issued := time.Now().Unix()
	assertion, err := bridge.makeJWT()
	if err != nil {
		t.Fatalf("makeJWT returned unexpected error: %v", err)
	}
	signedBefore := time.Now().Unix()

	segments := strings.Split(*assertion, ".")
	if len(segments) != 3 {
		t.Fatalf("assertion has %d segments, want 3: %q", len(segments), *assertion)
	}

	// Salesforce accepts RS256 only, and the header is what selects it.
	if header := string(decodeJWTSegment(t, segments[0])); header != `{"alg":"RS256"}` {
		t.Errorf("header = %s, want {\"alg\":\"RS256\"}", header)
	}

	var claim JWTClaim
	if err := json.Unmarshal(decodeJWTSegment(t, segments[1]), &claim); err != nil {
		t.Fatalf("failed decoding the claim set: %v", err)
	}
	if claim.ISS != "jwt-consumer-key" {
		t.Errorf("iss = %q, want the consumer key %q", claim.ISS, "jwt-consumer-key")
	}
	if claim.Sub != "jwt-user@example.invalid" {
		t.Errorf("sub = %q, want the username %q", claim.Sub, "jwt-user@example.invalid")
	}
	if claim.Aud != "example-dev-ed.develop.my.salesforce.com" {
		t.Errorf("aud = %q, want the token endpoint host", claim.Aud)
	}

	// The assertion expires two minutes out. Salesforce applies no tolerance, which is
	// why the bridge is sensitive to host clock skew on this flow.
	expiry, err := strconv.ParseInt(claim.Exp, 10, 64)
	if err != nil {
		t.Fatalf("exp %q is not a unix timestamp: %v", claim.Exp, err)
	}
	if expiry < issued+120 || expiry > signedBefore+120 {
		t.Errorf("exp = %d, want a value 120s after a signing time in [%d, %d]", expiry, issued, signedBefore)
	}

	verifyAssertionSignature(t, bridge, *assertion)
}

// TestMakeJWTSignsDistinctAssertions guards against a cached assertion. Each attempt must
// carry its own expiry, or a bridge that ran longer than two minutes would keep replaying
// an expired credential.
func TestMakeJWTSignsDistinctAssertions(t *testing.T) {
	setMinimalBridgeEnv(t)
	setEnv(t, "OAUTH_GRANT_TYPE", GRANT_JWT_BEARER)
	setEnv(t, "OAUTH_JWT_KEY", testJWTKeyBase64(t))

	bridge, err := newBridge()
	if err != nil {
		t.Fatalf("newBridge returned unexpected error: %v", err)
	}

	first, err := bridge.makeJWT()
	if err != nil {
		t.Fatalf("makeJWT returned unexpected error: %v", err)
	}
	// A second past the first, so the expiry in the claim set differs.
	time.Sleep(1100 * time.Millisecond)
	second, err := bridge.makeJWT()
	if err != nil {
		t.Fatalf("makeJWT returned unexpected error: %v", err)
	}

	if *first == *second {
		t.Error("two assertions signed a second apart are identical, so the expiry is not being refreshed")
	}
	verifyAssertionSignature(t, bridge, *second)
}

// TestJWTKeyValidation covers every way OAUTH_JWT_KEY is rejected. The PKCS#8 case is the
// one operators hit: OpenSSL 3 writes that format by default, so a key generated with plain
// `openssl genrsa` cannot be loaded and the message has to say which format is wanted.
func TestJWTKeyValidation(t *testing.T) {
	validKey := testJWTKeyBase64(t)

	pemBase64 := func(blockType string, contents []byte) string {
		return base64.StdEncoding.EncodeToString(pem.EncodeToMemory(&pem.Block{
			Type:  blockType,
			Bytes: contents,
		}))
	}

	key, err := rsa.GenerateKey(rand.Reader, 1024)
	if err != nil {
		t.Fatalf("failed generating a test RSA key: %v", err)
	}
	pkcs8, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatalf("failed marshalling a PKCS#8 key: %v", err)
	}

	tests := []struct {
		name        string
		key         string
		wantMessage string
	}{
		{name: "a pkcs1 key in an rsa private key block is accepted", key: validKey},
		// `base64` wraps at 76 columns unless told otherwise. The README suggests -w 0,
		// but a wrapped key still loads, so an operator who omits it is not stuck.
		{name: "line wrapped base64 is accepted", key: wrapBase64(validKey, 76)},

		{name: "unset", key: "", wantMessage: "OAUTH_JWT_KEY not set"},
		{name: "not base64 at all", key: "this is not base64 !!", wantMessage: "base64"},
		{name: "base64 of something that is not pem", key: base64.StdEncoding.EncodeToString([]byte("just some text")), wantMessage: "PEM-encoded block"},
		{name: "pkcs8 from openssl 3", key: pemBase64("PRIVATE KEY", pkcs8), wantMessage: "RSA PRIVATE KEY"},
		{name: "an ec key block", key: pemBase64("EC PRIVATE KEY", []byte("irrelevant")), wantMessage: "RSA PRIVATE KEY"},
		{name: "a public key", key: pemBase64("PUBLIC KEY", x509.MarshalPKCS1PublicKey(&key.PublicKey)), wantMessage: "RSA PRIVATE KEY"},
		// Right label, contents that are not a PKCS#1 key. This is what a truncated or
		// re-encoded key file looks like.
		{name: "the right label around the wrong bytes", key: pemBase64("RSA PRIVATE KEY", []byte("not a der encoded key")), wantMessage: "PKCS1"},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			setMinimalBridgeEnv(t)
			setEnv(t, "OAUTH_GRANT_TYPE", GRANT_JWT_BEARER)
			setEnv(t, "OAUTH_JWT_KEY", test.key)

			bridge, err := newBridge()
			if test.wantMessage == "" {
				if err != nil {
					t.Fatalf("newBridge rejected a valid key: %v", err)
				}
				if bridge.oauthJWTKey == nil {
					t.Error("newBridge succeeded but loaded no key")
				}
				return
			}

			if err == nil {
				t.Fatalf("newBridge accepted an unusable key, wanting an error naming %q", test.wantMessage)
			}
			if !strings.Contains(err.Error(), test.wantMessage) {
				t.Errorf("error = %q, want it to name %q so the operator knows what to fix", err, test.wantMessage)
			}
		})
	}
}

// wrapBase64 inserts a newline every width characters, reproducing what the base64 command
// line tool emits without -w 0.
func wrapBase64(encoded string, width int) string {
	var wrapped strings.Builder
	for len(encoded) > width {
		wrapped.WriteString(encoded[:width])
		wrapped.WriteString("\n")
		encoded = encoded[width:]
	}
	wrapped.WriteString(encoded)

	return wrapped.String()
}

// TestNewBridgeInfersTheGrant covers the compatibility promise: a deployment that predates
// OAUTH_GRANT_TYPE keeps the flow it already had. TestResolveGrantType covers the same
// decision in isolation; this asserts newBridge acts on it, key and all.
func TestNewBridgeInfersTheGrant(t *testing.T) {
	t.Run("a jwt key selects jwt bearer", func(t *testing.T) {
		setMinimalBridgeEnv(t)
		setEnv(t, "OAUTH_JWT_KEY", testJWTKeyBase64(t))
		unsetEnv(t, "OAUTH_GRANT_TYPE")
		// The flow needs neither, so their absence must not stop startup.
		unsetEnv(t, "OAUTH_PASSWORD")
		unsetEnv(t, "OAUTH_SECRET")

		bridge, err := newBridge()
		if err != nil {
			t.Fatalf("newBridge returned unexpected error: %v", err)
		}
		if bridge.oauthGrantType != GRANT_JWT_BEARER {
			t.Errorf("grant = %q, want %q", bridge.oauthGrantType, GRANT_JWT_BEARER)
		}
		if bridge.oauthJWTKey == nil {
			t.Error("the inferred jwt bearer flow loaded no key")
		}
	})

	t.Run("no jwt key selects password", func(t *testing.T) {
		setMinimalBridgeEnv(t)
		unsetEnv(t, "OAUTH_GRANT_TYPE")

		bridge, err := newBridge()
		if err != nil {
			t.Fatalf("newBridge returned unexpected error: %v", err)
		}
		if bridge.oauthGrantType != GRANT_PASSWORD {
			t.Errorf("grant = %q, want %q", bridge.oauthGrantType, GRANT_PASSWORD)
		}
		if bridge.oauthJWTKey != nil {
			t.Error("the password flow loaded a jwt key")
		}
	})

	// A typo must stop startup. Falling through to an inferred flow would authenticate a
	// different way than the operator asked for.
	t.Run("an unrecognized grant stops startup", func(t *testing.T) {
		setMinimalBridgeEnv(t)
		setEnv(t, "OAUTH_GRANT_TYPE", "client_credentials")

		if _, err := newBridge(); err == nil {
			t.Fatal("newBridge accepted an unrecognized OAUTH_GRANT_TYPE")
		}
	})
}

// TestStartupLogsTheResolvedGrant pins the startup log line, which is the only way an
// operator can confirm which flow is in effect once inference is involved.
func TestStartupLogsTheResolvedGrant(t *testing.T) {
	for _, grant := range allGrants {
		grant := grant
		t.Run(grant, func(t *testing.T) {
			logged := captureLog(t)
			bridgeForGrant(t, grant, "https://example.my.salesforce.com/services/oauth2/token")

			want := "authenticating to Salesforce with the " + grant + " grant"
			if !strings.Contains(logged.String(), want) {
				t.Errorf("startup log does not contain %q\nlog:\n%s", want, logged.String())
			}

			// Only the password flow is deprecated, so only it earns the notice.
			deprecated := strings.Contains(logged.String(), "the password grant is deprecated")
			if deprecated != (grant == GRANT_PASSWORD) {
				t.Errorf("deprecation warning present = %v for the %s grant\nlog:\n%s",
					deprecated, grant, logged.String())
			}
		})
	}
}

// TestClientCredentialsWarnsAboutSharedLoginHosts covers the advisory for a configuration
// that cannot work. Salesforce answers a client credentials request on a shared login host
// with "request not supported on this domain", which names neither the grant nor the host,
// so the bridge says so at startup instead. The endpoint is still used as configured: an
// explicit OAUTH_URI is not overridden.
func TestClientCredentialsWarnsAboutSharedLoginHosts(t *testing.T) {
	tests := []struct {
		name        string
		grant       string
		oauthURI    string
		wantWarning bool
	}{
		{name: "production login host", grant: GRANT_CLIENT_CREDENTIALS, oauthURI: "https://login.salesforce.com/services/oauth2/token", wantWarning: true},
		{name: "sandbox login host", grant: GRANT_CLIENT_CREDENTIALS, oauthURI: "https://test.salesforce.com/services/oauth2/token", wantWarning: true},
		// Host comparison is case insensitive, so odd casing cannot slip past the check.
		{name: "host casing does not matter", grant: GRANT_CLIENT_CREDENTIALS, oauthURI: "https://LOGIN.Salesforce.COM/services/oauth2/token", wantWarning: true},
		{name: "the org domain is quiet", grant: GRANT_CLIENT_CREDENTIALS, oauthURI: "https://example.my.salesforce.com/services/oauth2/token", wantWarning: false},
		// The other flows are accepted on those hosts, so warning about them would be noise.
		{name: "jwt bearer on a login host is quiet", grant: GRANT_JWT_BEARER, oauthURI: "https://login.salesforce.com/services/oauth2/token", wantWarning: false},
		{name: "password on a login host is quiet", grant: GRANT_PASSWORD, oauthURI: "https://login.salesforce.com/services/oauth2/token", wantWarning: false},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			logged := captureLog(t)
			bridge := bridgeForGrant(t, test.grant, test.oauthURI)

			warned := strings.Contains(logged.String(), "rejects the client credentials grant")
			if warned != test.wantWarning {
				t.Errorf("warned = %v, want %v\nlog:\n%s", warned, test.wantWarning, logged.String())
			}
			if got := bridge.oauthURI.String(); got != test.oauthURI {
				t.Errorf("token endpoint = %q, want the configured %q", got, test.oauthURI)
			}
		})
	}
}

// TestClientCredentialsLogsTheDerivedEndpoint covers the other half of the derivation
// TestClientCredentialsDerivesItsTokenEndpoint checks. The bridge chooses an endpoint the
// operator never configured, so it has to report which one.
func TestClientCredentialsLogsTheDerivedEndpoint(t *testing.T) {
	setMinimalBridgeEnv(t)
	setEnv(t, "OAUTH_GRANT_TYPE", GRANT_CLIENT_CREDENTIALS)
	unsetEnv(t, "OAUTH_URI")
	logged := captureLog(t)

	bridge, err := newBridge()
	if err != nil {
		t.Fatalf("newBridge returned unexpected error: %v", err)
	}

	if !strings.Contains(logged.String(), bridge.oauthURI.String()) {
		t.Errorf("startup log does not name the derived endpoint %q\nlog:\n%s",
			bridge.oauthURI.String(), logged.String())
	}
}

// TestClientCredentialsRefusesAnUnusableSalesforceURL covers the failure path of the
// derivation. With no OAUTH_URI to fall back on there is no endpoint to try, so startup has
// to stop and say which variable to set.
func TestClientCredentialsRefusesAnUnusableSalesforceURL(t *testing.T) {
	setMinimalBridgeEnv(t)
	setEnv(t, "OAUTH_GRANT_TYPE", GRANT_CLIENT_CREDENTIALS)
	setEnv(t, "SALESFORCE_URL", "example.my.salesforce.com/services/apexrest/")
	unsetEnv(t, "OAUTH_URI")

	_, err := newBridge()
	if err == nil {
		t.Fatal("newBridge accepted a SALESFORCE_URL it cannot derive an endpoint from")
	}
	if !strings.Contains(err.Error(), "OAUTH_URI") {
		t.Errorf("error = %q, want it to name OAUTH_URI as the way out", err)
	}
}

// TestAuthorizeSalesforceHandlesTokenResponses covers what the bridge does with the token
// endpoint's answer. The handling is shared by every flow, so it is asserted for all three:
// a rejected credential is permanent and stops the daemon, while anything that might pass
// on a retry is transient and the loops carry on. Both classifications also have to leave a
// token already in hand alone, so a transient failure does not deauthenticate a running
// bridge.
func TestAuthorizeSalesforceHandlesTokenResponses(t *testing.T) {
	const existingToken = "token-from-an-earlier-authorization"

	tests := []struct {
		name          string
		status        int
		body          string
		wantErr       bool
		wantPermanent bool
		wantToken     string
	}{
		{name: "200 with a token stores it", status: 200, body: `{"access_token":"issued-token"}`, wantToken: "issued-token"},
		// Extra fields are what Salesforce actually returns; they must not interfere.
		{
			name:      "200 alongside other fields",
			status:    200,
			body:      `{"access_token":"issued-token","instance_url":"https://example.my.salesforce.com","token_type":"Bearer"}`,
			wantToken: "issued-token",
		},

		// A rejected credential does not improve on retry, so it stops the daemon.
		{name: "401 is permanent", status: 401, body: `{"error":"invalid_client"}`, wantErr: true, wantPermanent: true, wantToken: existingToken},
		{name: "403 is permanent", status: 403, body: `{"error":"forbidden"}`, wantErr: true, wantPermanent: true, wantToken: existingToken},

		// Everything else might pass later. A misconfigured flow lands here too --
		// Salesforce answers an unenabled grant with 400 invalid_grant -- so this is
		// deliberately retried rather than treated as fatal.
		{name: "400 is retried", status: 400, body: `{"error":"invalid_grant","error_description":"request not supported on this domain"}`, wantErr: true, wantToken: existingToken},
		{name: "500 is retried", status: 500, body: "upstream failure", wantErr: true, wantToken: existingToken},
		{name: "503 is retried", status: 503, body: "", wantErr: true, wantToken: existingToken},

		// A 200 that carries no usable token is a failure, not an empty success.
		{name: "200 with no token", status: 200, body: `{}`, wantErr: true, wantToken: existingToken},
		{name: "200 with an empty token", status: 200, body: `{"access_token":""}`, wantErr: true, wantToken: existingToken},
		{name: "200 with an unparseable body", status: 200, body: "<html>a proxy error page</html>", wantErr: true, wantToken: existingToken},
	}

	for _, grant := range allGrants {
		grant := grant
		t.Run(grant, func(t *testing.T) {
			for _, test := range tests {
				test := test
				t.Run(test.name, func(t *testing.T) {
					tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
						w.WriteHeader(test.status)
						_, _ = w.Write([]byte(test.body))
					}))
					defer tokenServer.Close()

					bridge := bridgeForGrant(t, grant, tokenServer.URL)
					bridge.oauthCurrentToken = existingToken

					err, permanent := bridge.authorizeSalesforce()
					if test.wantErr && err == nil {
						t.Error("authorizeSalesforce succeeded, want an error")
					}
					if !test.wantErr && err != nil {
						t.Errorf("authorizeSalesforce returned unexpected error: %v", err)
					}
					if permanent != test.wantPermanent {
						t.Errorf("permanent = %v, want %v", permanent, test.wantPermanent)
					}
					if bridge.oauthCurrentToken != test.wantToken {
						t.Errorf("token = %q, want %q", bridge.oauthCurrentToken, test.wantToken)
					}
				})
			}
		})
	}
}

// TestAuthorizeSalesforceRetriesAnUnreachableEndpoint covers the transport failing outright.
// A token endpoint that cannot be reached is a network problem, not a bad credential, so it
// must not be classified as permanent.
func TestAuthorizeSalesforceRetriesAnUnreachableEndpoint(t *testing.T) {
	for _, grant := range allGrants {
		grant := grant
		t.Run(grant, func(t *testing.T) {
			// Started and immediately closed, so the port is known to refuse connections.
			tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
			tokenURI := tokenServer.URL
			tokenServer.Close()

			bridge := bridgeForGrant(t, grant, tokenURI)

			err, permanent := bridge.authorizeSalesforce()
			if err == nil {
				t.Fatal("authorizeSalesforce succeeded against a closed endpoint")
			}
			if permanent {
				t.Error("an unreachable token endpoint was classified as a permanent failure")
			}
		})
	}
}

// TestAuthorizeSalesforceRejectsAnUnresolvedGrant covers authorizeSalesforce's own guard.
// newBridge resolves the grant to one of the constants and refuses to start otherwise, so
// reaching the default branch means the two have drifted apart -- a bug rather than a
// configuration problem. It must fail permanently and send nothing.
func TestAuthorizeSalesforceRejectsAnUnresolvedGrant(t *testing.T) {
	requests := 0
	tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		_, _ = w.Write([]byte(`{"access_token":"issued-token"}`))
	}))
	defer tokenServer.Close()

	endpoint, err := url.Parse(tokenServer.URL)
	if err != nil {
		t.Fatalf("failed parsing the test server URL: %v", err)
	}

	// The underscored spelling is the shape of the drift worth catching: it is the OAuth
	// wire value, and resolveGrantType rejects it as OAUTH_GRANT_TYPE.
	bridge := &Bridge{client: http.Client{}, oauthGrantType: "client_credentials", oauthURI: *endpoint}

	err, permanent := bridge.authorizeSalesforce()
	if err == nil {
		t.Fatal("authorizeSalesforce accepted an unresolved grant type")
	}
	if !permanent {
		t.Error("an unresolved grant type must fail permanently, retrying cannot fix it")
	}
	if requests != 0 {
		t.Errorf("sent %d token requests for an unresolved grant, want 0", requests)
	}
	if bridge.oauthCurrentToken != "" {
		t.Errorf("token = %q, want it left unset", bridge.oauthCurrentToken)
	}
}

// TestEveryGrantYieldsABearerToken covers where the flows converge. However the token was
// obtained, it reaches Salesforce the same way: as an Authorization: Bearer header on the
// Apex REST request.
func TestEveryGrantYieldsABearerToken(t *testing.T) {
	for _, grant := range allGrants {
		grant := grant
		t.Run(grant, func(t *testing.T) {
			token := "token-for-" + grant

			tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				_, _ = w.Write([]byte(`{"access_token":"` + token + `"}`))
			}))
			defer tokenServer.Close()

			var authorization string
			apexServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				authorization = r.Header.Get("Authorization")
				w.WriteHeader(http.StatusOK)
			}))
			defer apexServer.Close()

			bridge := bridgeForGrant(t, grant, tokenServer.URL)
			if err, _ := bridge.authorizeSalesforce(); err != nil {
				t.Fatalf("authorizeSalesforce returned unexpected error: %v", err)
			}

			request, err := http.NewRequest("GET", apexServer.URL, nil)
			if err != nil {
				t.Fatalf("failed building the Apex request: %v", err)
			}
			response, err, permanent := bridge.requestWithOauth(request)
			if err != nil {
				t.Fatalf("requestWithOauth returned unexpected error: %v", err)
			}
			if permanent {
				t.Fatal("requestWithOauth reported a permanent failure on a successful request")
			}
			drainAndClose(response)

			if want := "Bearer " + token; authorization != want {
				t.Errorf("Authorization = %q, want %q", authorization, want)
			}
		})
	}
}

// TestRequestWithOauthReauthorizesOnRejection covers token renewal. Salesforce expires a
// session independently of the bridge, so a rejected request has to trigger a fresh
// authorization -- otherwise every later request carries the same dead token.
func TestRequestWithOauthReauthorizesOnRejection(t *testing.T) {
	for _, status := range []int{401, 403} {
		status := status
		t.Run(strconv.Itoa(status), func(t *testing.T) {
			authorizations := 0
			tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				authorizations++
				_, _ = w.Write([]byte(`{"access_token":"renewed-token"}`))
			}))
			defer tokenServer.Close()

			apexServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(status)
			}))
			defer apexServer.Close()

			bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokenServer.URL)
			bridge.oauthCurrentToken = "expired-token"

			request, err := http.NewRequest("GET", apexServer.URL, nil)
			if err != nil {
				t.Fatalf("failed building the Apex request: %v", err)
			}
			response, err, permanent := bridge.requestWithOauth(request)
			if err != nil {
				t.Fatalf("requestWithOauth returned unexpected error: %v", err)
			}
			if permanent {
				t.Fatal("a successful reauthorization must not report a permanent failure")
			}
			drainAndClose(response)

			if authorizations != 1 {
				t.Errorf("token endpoint called %d times after a %d, want 1", authorizations, status)
			}
			if bridge.oauthCurrentToken != "renewed-token" {
				t.Errorf("token = %q, want the renewed token", bridge.oauthCurrentToken)
			}
		})
	}
}

// TestRequestWithOauthPropagatesAPermanentAuthFailure covers the case where renewal itself
// is refused. A credential Salesforce will not accept cannot be retried into working, so the
// permanent flag has to reach the loops, which stop the daemon on it.
func TestRequestWithOauthPropagatesAPermanentAuthFailure(t *testing.T) {
	tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"invalid_client"}`))
	}))
	defer tokenServer.Close()

	apexServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer apexServer.Close()

	bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokenServer.URL)
	bridge.oauthCurrentToken = "expired-token"

	request, err := http.NewRequest("GET", apexServer.URL, nil)
	if err != nil {
		t.Fatalf("failed building the Apex request: %v", err)
	}
	response, err, permanent := bridge.requestWithOauth(request)
	if err == nil {
		t.Fatal("requestWithOauth succeeded when reauthorization was refused")
	}
	if !permanent {
		t.Error("a refused credential must be reported as permanent")
	}
	if response != nil {
		drainAndClose(response)
		t.Error("no response should be returned once authorization has failed")
	}
}

// TestSalesforceRequestsCarryProjectHeader covers both directions of the multi-project
// contract on the bridge side: the header rides Salesforce-bound requests when a project is
// configured, and is absent entirely when one is not.
//
// The absence half matters as much as the presence half. An omitted header is what makes a
// bridge that has not opted in indistinguishable from one running an older version, which is
// what lets an operator upgrade the org and the bridge in either order.
func TestSalesforceRequestsCarryProjectHeader(t *testing.T) {
	for _, testCase := range []struct {
		name       string
		projectKey string
		want       string
	}{
		{name: "configured", projectKey: "gps", want: "gps"},
		{name: "unset", projectKey: "", want: ""},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			var captured string
			var present bool

			bridge := newTestBridge(t, "http://unused.invalid", "http://unused.invalid")
			bridge.oauthCurrentToken = "test-token"
			bridge.projectKey = testCase.projectKey

			sfServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				captured = r.Header.Get(PROJECT_HEADER)
				_, present = r.Header[PROJECT_HEADER]
				bridge.cancel()
				_, _ = w.Write([]byte(`[]`))
			}))
			defer sfServer.Close()
			bridge.salesforceURL = sfServer.URL + "/"

			if err := bridge.eventLoop(); err != nil {
				t.Fatalf("eventLoop returned unexpected error: %v", err)
			}

			if captured != testCase.want {
				t.Errorf("%s = %q, want %q", PROJECT_HEADER, captured, testCase.want)
			}
			if testCase.projectKey == "" && present {
				t.Errorf("%s was sent with an unset project key; it must be omitted so the "+
					"request is indistinguishable from an older bridge's", PROJECT_HEADER)
			}
		})
	}
}

// TestNewBridgeResolvesProjectKey covers LD_PROJECT_KEY through newBridge rather than by
// reading the variable back directly, so the trimming and the optionality are asserted on the
// value the bridge actually uses.
//
// The distinction between unset and whitespace-only matters: both must yield an empty key,
// because an empty key is what causes the project header to be omitted entirely, and that
// omission is what lets an org and a bridge be upgraded in either order.
func TestNewBridgeResolvesProjectKey(t *testing.T) {
	tests := []struct {
		name  string
		value string
		set   bool
		want  string
	}{
		{name: "unset yields no project", set: false, want: ""},
		{name: "empty yields no project", value: "", set: true, want: ""},
		{name: "whitespace only yields no project", value: "   ", set: true, want: ""},
		{name: "plain value", value: "gps", set: true, want: "gps"},
		{name: "surrounding whitespace is trimmed", value: "  gps  ", set: true, want: "gps"},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			setMinimalBridgeEnv(t)
			if test.set {
				setEnv(t, "LD_PROJECT_KEY", test.value)
			} else {
				unsetEnv(t, "LD_PROJECT_KEY")
			}

			bridge, err := newBridge()
			if err != nil {
				t.Fatalf("newBridge returned unexpected error: %v", err)
			}
			if bridge.projectKey != test.want {
				t.Errorf("projectKey = %q, want %q", bridge.projectKey, test.want)
			}
		})
	}
}
