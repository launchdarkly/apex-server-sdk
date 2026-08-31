package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// Both loops build a push request from a URI assembled at run time, so construction can
// fail on a malformed one. Each used to answer that with a fixed string of its own and
// drop the error http.NewRequest produced, which left the operator with a message naming
// neither the URI nor what was wrong with it. These tests pin the underlying error
// reaching the caller.
//
// A control character is what url.Parse refuses, which is how each test forces the
// failure. Both fixtures assert the failure is reached before asserting anything about
// it, so a future stdlib that accepts these URLs fails loudly rather than passing
// vacuously.

// runLoop runs one of the bridge's loops to completion and returns its error. A loop that
// does not return is a failure in itself, so the wait is bounded.
//
// Each caller registers its server's Close before building the bridge, so t.Cleanup's LIFO
// order cancels the bridge first and only then shuts the server down. Keep that order: a
// loop still running on the timeout path must be told to stop before the server it is
// talking to disappears.
func runLoop(t *testing.T, loop func() error) error {
	t.Helper()

	done := make(chan error, 1)
	go func() {
		done <- loop()
	}()

	select {
	case err := <-done:
		return err
	case <-time.After(10 * time.Second):
		t.Fatal("the loop did not return; it is polling instead of reporting the error")
		return nil
	}
}

// TestEventLoopReturnsAPushRequestError covers the push to LaunchDarkly. The Salesforce
// stand-in hands over a non-empty batch, because an empty drain skips the push entirely
// and the loop would never reach the construction.
func TestEventLoopReturnsAPushRequestError(t *testing.T) {
	captureLog(t)

	salesforce := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`[{"kind":"feature"}]`))
	}))
	t.Cleanup(salesforce.Close)

	bridge := newTestBridge(t, "http://launchdarkly.invalid/", "http://events.invalid/\x7f")
	bridge.salesforceURL = salesforce.URL + "/"

	wantErr := requestConstructionError(t, "POST", bridge.launchDarklyEventsURI+"/bulk")

	err := runLoop(t, bridge.eventLoop)
	if err == nil {
		t.Fatal("eventLoop returned no error for an unbuildable push request")
	}

	if err.Error() != wantErr.Error() {
		t.Errorf("eventLoop returned %q, want the underlying error %q", err, wantErr)
	}
}

// TestFeatureLoopReturnsAPushRequestError covers the push to Salesforce. The LaunchDarkly
// stand-in answers 200 with a body, since a 304 or an error status would send the loop to
// its wait before the push is built.
func TestFeatureLoopReturnsAPushRequestError(t *testing.T) {
	captureLog(t)

	launchDarkly := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"flags":{},"segments":{}}`))
	}))
	t.Cleanup(launchDarkly.Close)

	bridge := newTestBridge(t, launchDarkly.URL, "http://events.invalid/")
	bridge.salesforceURL = "http://salesforce.invalid/\x7f/"

	wantErr := requestConstructionError(t, "POST", bridge.salesforceURL+"store")

	err := runLoop(t, bridge.featureLoop)
	if err == nil {
		t.Fatal("featureLoop returned no error for an unbuildable push request")
	}

	if err.Error() != wantErr.Error() {
		t.Errorf("featureLoop returned %q, want the underlying error %q", err, wantErr)
	}
}

// requestConstructionError reports what http.NewRequest says about a URI, so a test can
// expect that text rather than hard-coding Go's wording. It fails if the URI is accepted,
// since a fixture that builds cleanly proves nothing.
func requestConstructionError(t *testing.T, method, uri string) error {
	t.Helper()

	_, err := http.NewRequest(method, uri, strings.NewReader(""))
	if err == nil {
		t.Fatalf("http.NewRequest accepted %q, so this fixture no longer reaches the failure", uri)
	}

	return err
}
