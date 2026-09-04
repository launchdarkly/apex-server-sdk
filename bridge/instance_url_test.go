package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// lightningHostURL is what an operator who copies the URL out of the browser address bar
// configures. The Lightning host serves the UI and not the API.
const lightningHostURL = "https://mycompany.lightning.force.com/services/apexrest/"

// sessionHostURL stands in for an instance_url, so it is the bare origin Salesforce
// returns rather than an Apex REST URL. Its host differs from lightningHostURL's, which is
// the whole condition the diagnostic reports on.
const sessionHostURL = "https://mycompany.my.salesforce.com"

// hostMismatchMarker appears only in the mismatch hint, so it is a reliable test for that
// message alone.
const hostMismatchMarker = "Salesforce refused the request again after a token refresh"

// tokenDocument builds a token response naming instanceURL, matching what Salesforce
// returns on all three grants.
func tokenDocument(instanceURL string) string {
	return `{"access_token":"` + renewedToken + `","instance_url":"` + instanceURL + `"}`
}

// tokenServerWithBody answers every token request with body, and reports how many times it
// was asked. It differs from tokenServer in oauth_retry_test.go only in letting a test
// choose the document, which is how the instance_url in it is varied.
func tokenServerWithBody(t *testing.T, body string) (*httptest.Server, func() int) {
	t.Helper()
	var mu sync.Mutex
	authorizations := 0

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		authorizations++
		mu.Unlock()

		_, _ = w.Write([]byte(body))
	}))

	return server, func() int {
		mu.Lock()
		defer mu.Unlock()
		return authorizations
	}
}

// TestAuthCapturesTheSessionHost covers the capture on every grant. All three return
// instance_url, and the bridge must not depend on which one is in use.
func TestAuthCapturesTheSessionHost(t *testing.T) {
	for _, grant := range allGrants {
		grant := grant
		t.Run(grant, func(t *testing.T) {
			tokens, _ := tokenServerWithBody(t, tokenDocument(sessionHostURL))
			defer tokens.Close()

			bridge := bridgeForGrant(t, grant, tokens.URL)
			t.Cleanup(bridge.cancel)

			err, permanent := bridge.authorizeSalesforce()
			if err != nil {
				t.Fatalf("authorizeSalesforce returned unexpected error: %v", err)
			}
			if permanent {
				t.Fatal("a successful authentication must not report a permanent failure")
			}

			if bridge.salesforceInstanceURL != sessionHostURL {
				t.Errorf("salesforceInstanceURL = %q, want %q",
					bridge.salesforceInstanceURL, sessionHostURL)
			}
		})
	}
}

// TestSalesforceRequestsUseSalesforceURL pins the decision not to rebase. instance_url is
// captured to report on, and nothing more: a session host that differs from the configured
// one must not quietly redirect the requests, because a configured host that works is the
// only authority on whether the configuration is right.
func TestSalesforceRequestsUseSalesforceURL(t *testing.T) {
	tests := []struct {
		name   string
		suffix string
		drive  func(bridge *Bridge) error
		// prepare points the bridge at a LaunchDarkly stub when the loop needs one.
		prepare func(t *testing.T, bridge *Bridge)
	}{
		{
			name:    "events",
			suffix:  "/event",
			drive:   func(bridge *Bridge) error { return bridge.eventLoop() },
			prepare: func(t *testing.T, bridge *Bridge) {},
		},
		{
			name:   "flags",
			suffix: "/store",
			drive:  func(bridge *Bridge) error { return bridge.featureLoop() },
			prepare: func(t *testing.T, bridge *Bridge) {
				ld := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					_, _ = w.Write([]byte(`{"flags":{},"segments":{}}`))
				}))
				t.Cleanup(ld.Close)

				bridge.launchDarklyBaseURI = ld.URL
			},
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			var cancel func()
			var mu sync.Mutex
			var paths []string

			salesforce := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				mu.Lock()
				paths = append(paths, r.URL.Path)
				mu.Unlock()

				cancel()
				// An empty array satisfies the event drain without a push to
				// LaunchDarkly, and the flag push reads only the status.
				_, _ = w.Write([]byte("[]"))
			}))
			defer salesforce.Close()

			// The session host is a host no test server listens on, so a rebased request
			// reaches nothing and the loop never gets here.
			tokens, _ := tokenServerWithBody(t, tokenDocument(sessionHostURL))
			defer tokens.Close()

			bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokens.URL)
			t.Cleanup(bridge.cancel)
			bridge.salesforceURL = salesforce.URL + "/"
			cancel = bridge.cancel
			test.prepare(t, bridge)

			if err, _ := bridge.authorizeSalesforce(); err != nil {
				t.Fatalf("authorizeSalesforce returned unexpected error: %v", err)
			}

			done := make(chan error, 1)
			go func() { done <- test.drive(bridge) }()

			select {
			case err := <-done:
				if err != nil {
					t.Fatalf("the loop returned unexpected error: %v", err)
				}
			case <-time.After(10 * time.Second):
				t.Fatal("the loop never reached the configured host; it is using the " +
					"session host from instance_url instead")
			}

			mu.Lock()
			defer mu.Unlock()
			if len(paths) == 0 {
				t.Fatal("the configured host served no requests")
			}
			if paths[0] != test.suffix {
				t.Errorf("first request path = %q, want %q", paths[0], test.suffix)
			}
		})
	}
}

// TestHostMismatchHintSpeaksOnlyOnASecondRefusal covers when the hint appears and, more
// importantly, when it does not. A difference between the two hosts is not evidence of
// anything on its own: a proxy or an older instance name routes perfectly well, so a
// request that succeeds settles the question and the hint must stay quiet.
func TestHostMismatchHintSpeaksOnlyOnASecondRefusal(t *testing.T) {
	refuseEvery := func(attempt int) int { return http.StatusUnauthorized }

	tests := []struct {
		name string
		// configured overrides SALESFORCE_URL when set.
		configured string
		tokenBody  string
		statusFor  func(attempt int) int
		wantHint   bool
	}{
		{
			name:      "refused twice with a different host",
			tokenBody: tokenDocument(sessionHostURL),
			statusFor: refuseEvery,
			wantHint:  true,
		},
		{
			// Salesforce reports an unusable session with either status, so both have to
			// reach the hint.
			name:      "refused twice with 403",
			tokenBody: tokenDocument(sessionHostURL),
			statusFor: func(attempt int) int { return http.StatusForbidden },
			wantHint:  true,
		},
		{
			// A routine token expiry. The retry succeeded, so the configuration works and
			// there is nothing to report however the two hosts compare.
			name:      "the retry succeeded",
			tokenBody: tokenDocument(sessionHostURL),
			statusFor: func(attempt int) int {
				if attempt == 1 {
					return http.StatusUnauthorized
				}
				return http.StatusOK
			},
			wantHint: false,
		},
		{
			name:      "the first attempt succeeded",
			tokenBody: tokenDocument(sessionHostURL),
			statusFor: func(attempt int) int { return http.StatusOK },
			wantHint:  false,
		},
		{
			// The case that decides whether the hint is a signal or noise. A correct
			// configuration is refused for some other reason -- revoked permissions, a
			// changed run-as identity -- and naming the two URLs would misdirect. It is
			// also what an equality test would get wrong, since SALESFORCE_URL carries
			// the Apex REST path and instance_url does not.
			name:       "a correct configuration",
			configured: sessionHostURL + "/services/apexrest/",
			tokenBody:  tokenDocument(sessionHostURL),
			statusFor:  refuseEvery,
			wantHint:   false,
		},
		{
			// The password grant returns instance_url with a trailing slash where the
			// other two leave it off, so the same correct configuration has to stay
			// silent against either form.
			name:       "a correct configuration against a trailing slash",
			configured: sessionHostURL + "/services/apexrest/",
			tokenBody:  tokenDocument(sessionHostURL + "/"),
			statusFor:  refuseEvery,
			wantHint:   false,
		},
		{
			name:       "a correct configuration differing only in case",
			configured: "https://MyCompany.My.Salesforce.com/services/apexrest/",
			tokenBody:  tokenDocument(sessionHostURL),
			statusFor:  refuseEvery,
			wantHint:   false,
		},
		{
			// Nothing to compare against, so nothing to say.
			name:      "no instance_url",
			tokenBody: `{"access_token":"` + renewedToken + `"}`,
			statusFor: refuseEvery,
			wantHint:  false,
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			apex, _ := apexServer(t, test.statusFor)
			defer apex.Close()

			tokens, _ := tokenServerWithBody(t, test.tokenBody)
			defer tokens.Close()

			bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokens.URL)
			t.Cleanup(bridge.cancel)
			bridge.salesforceURL = lightningHostURL
			if test.configured != "" {
				bridge.salesforceURL = test.configured
			}
			bridge.oauthCurrentToken = staleToken

			logged := captureLog(t)

			response, err, permanent := bridge.requestWithOauth(apexRequest(t, apex.URL))
			if err != nil {
				t.Fatalf("requestWithOauth returned unexpected error: %v", err)
			}
			if permanent {
				t.Fatal("requestWithOauth reported a permanent failure unexpectedly")
			}
			if response == nil {
				t.Fatal("requestWithOauth returned neither a response nor an error")
			}
			drainAndClose(response)

			hinted := strings.Contains(logged.String(), hostMismatchMarker)
			if hinted != test.wantHint {
				t.Errorf("hinted = %v, want %v\nlog:\n%s", hinted, test.wantHint, logged.String())
			}
		})
	}
}

// apexRequest builds the Salesforce-bound request these tests hand to requestWithOauth.
func apexRequest(t *testing.T, uri string) *http.Request {
	t.Helper()
	request, err := http.NewRequest("GET", uri, nil)
	if err != nil {
		t.Fatalf("failed building the Apex request: %v", err)
	}

	return request
}

// TestHintNamesNoURLs is the invariant of this design: a URL can carry a credential in its
// userinfo, so neither the configured one nor the one Salesforce returned may reach the log.
// The fixtures use hosts that appear nowhere else, so the assertion cannot pass by accident.
func TestHintNamesNoURLs(t *testing.T) {
	const (
		configuredURL = "https://never-log-this-configured.example.invalid/services/apexrest/"
		sessionURL    = "https://never-log-this-session.example.invalid"
	)

	apex, _ := apexServer(t, func(attempt int) int { return http.StatusUnauthorized })
	defer apex.Close()

	tokens, _ := tokenServerWithBody(t, tokenDocument(sessionURL))
	defer tokens.Close()

	bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokens.URL)
	t.Cleanup(bridge.cancel)
	bridge.salesforceURL = configuredURL
	bridge.oauthCurrentToken = staleToken

	logged := captureLog(t)

	response, err, _ := bridge.requestWithOauth(apexRequest(t, apex.URL))
	if err != nil {
		t.Fatalf("requestWithOauth returned unexpected error: %v", err)
	}
	drainAndClose(response)

	// The hint has to have fired, or this test passes on the strength of saying nothing.
	if !strings.Contains(logged.String(), hostMismatchMarker) {
		t.Fatalf("the hint did not fire, so nothing was asserted\nlog:\n%s", logged.String())
	}

	// The hosts are checked as well as the whole URLs, so that printing any part of either
	// is caught.
	for _, forbidden := range []string{
		configuredURL,
		sessionURL,
		"never-log-this-configured.example.invalid",
		"never-log-this-session.example.invalid",
	} {
		if strings.Contains(logged.String(), forbidden) {
			t.Errorf("the log names %q\nlog:\n%s", forbidden, logged.String())
		}
	}
}

// TestHostMismatchHintRepeatsEveryCycle pins the choice to speak on every failure rather
// than once per process. A persistent mismatch means the bridge is delivering nothing, and
// the failure it explains is logged every cycle, so a reader who starts tailing late or
// greps a window still has to find it.
func TestHostMismatchHintRepeatsEveryCycle(t *testing.T) {
	// Two per cycle: the original attempt and the retry after the refresh.
	const refusalsForTwoCycles = 4

	var cancel func()
	var mu sync.Mutex
	refusals := 0

	salesforce := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		refusals++
		enough := refusals >= refusalsForTwoCycles
		mu.Unlock()

		if enough {
			cancel()
		}

		w.Header().Set("Connection", "close")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`[{"errorCode":"INVALID_SESSION_ID"}]`))
	}))
	defer salesforce.Close()

	tokens, _ := tokenServerWithBody(t, tokenDocument(sessionHostURL))
	defer tokens.Close()

	bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokens.URL)
	t.Cleanup(bridge.cancel)
	bridge.salesforceURL = salesforce.URL + "/"
	bridge.eventPollInterval = time.Millisecond
	cancel = bridge.cancel

	logged := captureLog(t)

	done := make(chan error, 1)
	go func() { done <- bridge.eventLoop() }()

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("eventLoop returned unexpected error: %v", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("eventLoop did not finish")
	}

	if got := strings.Count(logged.String(), hostMismatchMarker); got < 2 {
		t.Errorf("the hint appeared %d times across two failing cycles, want at least 2\nlog:\n%s",
			got, logged.String())
	}
}

// TestConcurrentLoopsReadTheSessionHostSafely covers the protection on the captured host.
// Both loops authenticate through requestWithOauth, so one can rewrite the host while the
// other reads it to decide whether to hint.
//
// The Apex stub refuses everything, so each cycle on each loop writes the host and then
// reads it. Under -race an unsynchronized read is reported here and nowhere else, because
// no other test runs the two loops together.
func TestConcurrentLoopsReadTheSessionHostSafely(t *testing.T) {
	const refusalsUntilShutdown = 20

	var cancel func()
	var mu sync.Mutex
	refusals := 0

	salesforce := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		refusals++
		enough := refusals >= refusalsUntilShutdown
		mu.Unlock()

		if enough {
			cancel()
		}

		w.Header().Set("Connection", "close")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`[{"errorCode":"INVALID_SESSION_ID"}]`))
	}))
	defer salesforce.Close()

	ld := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"flags":{},"segments":{}}`))
	}))
	defer ld.Close()

	tokens, _ := tokenServerWithBody(t, tokenDocument(sessionHostURL))
	defer tokens.Close()

	bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokens.URL)
	t.Cleanup(bridge.cancel)
	bridge.salesforceURL = salesforce.URL + "/"
	bridge.launchDarklyBaseURI = ld.URL
	bridge.eventPollInterval = time.Millisecond
	bridge.flagPollInterval = time.Millisecond
	cancel = bridge.cancel

	// Started the way run() starts them, so the two loops contend for the same bridge.
	done := make(chan error, 2)
	go func() { done <- bridge.eventLoop() }()
	go func() { done <- bridge.featureLoop() }()

	for i := 0; i < 2; i++ {
		select {
		case err := <-done:
			if err != nil {
				t.Fatalf("a loop returned unexpected error: %v", err)
			}
		case <-time.After(30 * time.Second):
			t.Fatal("a loop did not shut down")
		}
	}

	bridge.lock.Lock()
	defer bridge.lock.Unlock()
	if bridge.salesforceInstanceURL != sessionHostURL {
		t.Errorf("salesforceInstanceURL = %q after the run, want %q",
			bridge.salesforceInstanceURL, sessionHostURL)
	}
}
