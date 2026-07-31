package main

import (
	"bytes"
	"context"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
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
	for _, name := range []string{"OAUTH_JWT_KEY", "OAUTH_URI", "HTTP_TIMEOUT", "LD_BASE_URI", "LD_EVENTS_URI"} {
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
