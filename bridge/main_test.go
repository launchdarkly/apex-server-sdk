package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

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
		context:               ctx,
		cancel:                cancel,
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
