package main

import (
	"bytes"
	"io/ioutil"
	"net/http"
	"net/http/httptest"
	"strconv"
	"sync"
	"testing"
	"time"
)

// staleToken is what a test bridge starts out holding, standing in for a token whose
// Salesforce session has since ended. renewedToken is what the fake token endpoint hands
// back, so an attempt carrying it can only be one made after a refresh.
const (
	staleToken   = "stale-token"
	renewedToken = "renewed-token"
)

// tokenServer answers every request with renewedToken and reports how many times it was
// asked. The refresh count is what separates one retry from a loop of them, so every test
// here checks it.
func tokenServer(t *testing.T) (*httptest.Server, func() int) {
	t.Helper()
	var mu sync.Mutex
	refreshes := 0

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		refreshes++
		mu.Unlock()

		_, _ = w.Write([]byte(`{"access_token":"` + renewedToken + `"}`))
	}))

	return server, func() int {
		mu.Lock()
		defer mu.Unlock()
		return refreshes
	}
}

// apexAttempt records one request the fake Apex REST endpoint served.
type apexAttempt struct {
	authorization string
	body          []byte
}

// apexServer stands in for the Apex REST endpoint. statusFor picks the status of each
// attempt from its one-based number, which is how a test says "reject the first one and
// accept the rest" or "reject every one".
//
// Every attempt is recorded rather than just counted, because the interesting assertions
// are comparisons between attempts: whether the second carried the new token, and whether
// it carried the same body as the first.
//
// A rejection closes the connection, which forces the retry to dial a fresh one. That is
// deliberate, and it is what makes the body assertions mean anything. When a retry goes
// out on a pooled connection the transport covers for a body that was not replayed: it
// notices the request declared a ContentLength and wrote nothing, rewinds through GetBody
// and sends it again itself. It only does that on a reused connection, so a test that
// stays on one cannot tell a correct replay from a missing one.
func apexServer(t *testing.T, statusFor func(attempt int) int) (*httptest.Server, func() []apexAttempt) {
	t.Helper()
	var mu sync.Mutex
	var attempts []apexAttempt

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, err := ioutil.ReadAll(r.Body)
		if err != nil {
			t.Errorf("failed reading the request body: %v", err)
		}

		mu.Lock()
		attempts = append(attempts, apexAttempt{
			authorization: r.Header.Get("Authorization"),
			body:          body,
		})
		attempt := len(attempts)
		mu.Unlock()

		status := statusFor(attempt)
		if status == http.StatusUnauthorized || status == http.StatusForbidden {
			w.Header().Set("Connection", "close")
			w.WriteHeader(status)
			// Salesforce reports an ended session with a body, and that body is what
			// goes unreleased if the response is abandoned.
			_, _ = w.Write([]byte(`[{"errorCode":"INVALID_SESSION_ID"}]`))
			return
		}
		w.WriteHeader(status)
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))

	// A copy, so a caller reading the attempts cannot race an append that a still-running
	// handler is about to make.
	return server, func() []apexAttempt {
		mu.Lock()
		defer mu.Unlock()
		served := make([]apexAttempt, len(attempts))
		copy(served, attempts)

		return served
	}
}

// TestRequestWithOauthRetriesAfterRefresh covers the point of the change: a refreshed
// token is used at once rather than on the next cycle. Salesforce ends a session on its
// own schedule, so an expiry is routine, and handing the rejection back to the caller made
// every one of them cost a whole poll interval of stale flag data or undelivered events.
func TestRequestWithOauthRetriesAfterRefresh(t *testing.T) {
	// Salesforce reports an unusable session with either status, so both have to drive the
	// retry.
	for _, status := range []int{401, 403} {
		status := status
		t.Run(strconv.Itoa(status), func(t *testing.T) {
			tokens, refreshCount := tokenServer(t)
			defer tokens.Close()

			apex, attemptsOf := apexServer(t, func(attempt int) int {
				if attempt == 1 {
					return status
				}
				return http.StatusOK
			})
			defer apex.Close()

			bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokens.URL)
			bridge.oauthCurrentToken = staleToken

			request, err := http.NewRequest("GET", apex.URL, nil)
			if err != nil {
				t.Fatalf("failed building the Apex request: %v", err)
			}

			response, err, permanent := bridge.requestWithOauth(request)
			if err != nil {
				t.Fatalf("requestWithOauth returned unexpected error: %v", err)
			}
			if permanent {
				t.Fatal("a successful retry must not report a permanent failure")
			}
			if response == nil {
				t.Fatal("requestWithOauth returned neither a response nor an error")
			}
			defer drainAndClose(response)

			// The caller has to be given the retry's answer. Returning the original
			// rejection is what turned a refresh into a wasted cycle.
			if response.StatusCode != http.StatusOK {
				t.Errorf("returned status = %d, want the retry's 200", response.StatusCode)
			}

			attempts := attemptsOf()
			if len(attempts) != 2 {
				t.Fatalf("Apex served %d attempts, want 2: the rejected one and the retry",
					len(attempts))
			}
			if want := "Bearer " + staleToken; attempts[0].authorization != want {
				t.Errorf("first attempt Authorization = %q, want %q",
					attempts[0].authorization, want)
			}
			// The retry has to read the token back out of the bridge. Resending the
			// refused one would spend a round trip on a guaranteed rejection.
			if want := "Bearer " + renewedToken; attempts[1].authorization != want {
				t.Errorf("retry Authorization = %q, want %q", attempts[1].authorization, want)
			}
			if refreshes := refreshCount(); refreshes != 1 {
				t.Errorf("token endpoint called %d times, want 1", refreshes)
			}
		})
	}
}

// TestRequestWithOauthRetriesOnlyOnce covers termination. A token minted seconds ago being
// refused is not an expiry, so refreshing again cannot change the answer -- the connected
// app's permissions or its run-as identity changed. Recursing or looping on that would
// turn a standing misconfiguration into unbounded requests against the org's 24-hour API
// allocation, which is shared with every other client in the org.
func TestRequestWithOauthRetriesOnlyOnce(t *testing.T) {
	for _, status := range []int{401, 403} {
		status := status
		t.Run(strconv.Itoa(status), func(t *testing.T) {
			tokens, refreshCount := tokenServer(t)
			defer tokens.Close()

			// Every attempt is rejected, however fresh the token it carries.
			apex, attemptsOf := apexServer(t, func(int) int { return status })
			defer apex.Close()

			bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokens.URL)
			bridge.oauthCurrentToken = staleToken

			request, err := http.NewRequest("GET", apex.URL, nil)
			if err != nil {
				t.Fatalf("failed building the Apex request: %v", err)
			}

			response, err, permanent := bridge.requestWithOauth(request)
			if err != nil {
				t.Fatalf("requestWithOauth returned unexpected error: %v", err)
			}
			// The refresh itself succeeded, so nothing here is an authorization failure.
			// Reporting one would stop the daemon on what the loops handle by waiting.
			if permanent {
				t.Fatal("a rejected retry must not be reported as a permanent failure")
			}
			if response == nil {
				t.Fatal("requestWithOauth returned neither a response nor an error")
			}
			defer drainAndClose(response)

			// The retry's own rejection is what the caller logs and acts on.
			if response.StatusCode != status {
				t.Errorf("returned status = %d, want %d", response.StatusCode, status)
			}
			if attempts := attemptsOf(); len(attempts) != 2 {
				t.Errorf("Apex served %d attempts, want exactly 2", len(attempts))
			}
			if refreshes := refreshCount(); refreshes != 1 {
				t.Errorf("token endpoint called %d times, want exactly 1", refreshes)
			}
		})
	}
}

// TestRequestWithOauthRetriesOnlyRejectedTokens fixes the boundary of the retry. Only a
// 401 or a 403 says the token is what went wrong, and only those are worth sending again
// with a new one. Anything else is already retried by the caller's next poll, so sending
// it twice here would double the requests a failing endpoint receives without changing the
// outcome -- and a refresh on a healthy 200 would discard a working session for nothing.
func TestRequestWithOauthRetriesOnlyRejectedTokens(t *testing.T) {
	tests := []struct {
		name   string
		status int
	}{
		{name: "success", status: 200},
		{name: "not found", status: 404},
		{name: "server error", status: 500},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			tokens, refreshCount := tokenServer(t)
			defer tokens.Close()

			apex, attemptsOf := apexServer(t, func(int) int { return test.status })
			defer apex.Close()

			bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokens.URL)
			bridge.oauthCurrentToken = staleToken

			request, err := http.NewRequest("GET", apex.URL, nil)
			if err != nil {
				t.Fatalf("failed building the Apex request: %v", err)
			}

			response, err, permanent := bridge.requestWithOauth(request)
			if err != nil {
				t.Fatalf("requestWithOauth returned unexpected error: %v", err)
			}
			if permanent {
				t.Fatal("no authorization was attempted, so nothing can be permanent")
			}
			if response == nil {
				t.Fatal("requestWithOauth returned neither a response nor an error")
			}
			defer drainAndClose(response)

			if response.StatusCode != test.status {
				t.Errorf("returned status = %d, want %d", response.StatusCode, test.status)
			}
			if attempts := attemptsOf(); len(attempts) != 1 {
				t.Errorf("Apex served %d attempts for a %d, want exactly 1",
					len(attempts), test.status)
			}
			if refreshes := refreshCount(); refreshes != 0 {
				t.Errorf("token endpoint called %d times for a %d, want 0",
					refreshes, test.status)
			}
			// The token in hand is still the one that worked, so a non-auth status must
			// not have replaced it.
			if bridge.oauthCurrentToken != staleToken {
				t.Errorf("token = %q, want it left untouched", bridge.oauthCurrentToken)
			}
		})
	}
}

// flagPayload is the flag data the fake LaunchDarkly endpoint serves, and so the exact
// bytes a flag push has to carry. It is long enough that a truncated replay would not
// match it by accident.
const flagPayload = `{"flags":{"alpha":{"key":"alpha","version":3},"beta":{"key":"beta","version":7}},"segments":{}}`

// TestFeatureLoopRetriesTheFlagPushWithTheCompleteBody covers the retry at the only call
// site that sends a body. The transport consumes and closes the body while writing the
// first attempt, so a retry that did not replay it would send the right headers with
// nothing behind them -- and the push would fail, which looks exactly like the problem the
// retry exists to fix.
//
// The rejection closes the connection, so the retry dials rather than reusing the pool. See
// apexServer: on a reused connection the transport replays the body itself and a missing
// replay leaves no trace, so a test that stays on one proves nothing.
//
// Byte equality between the two attempts is then the assertion that matters. Checking only
// that the body is non-empty would also pass a truncated or reordered replay.
func TestFeatureLoopRetriesTheFlagPushWithTheCompleteBody(t *testing.T) {
	tokens, refreshCount := tokenServer(t)
	defer tokens.Close()

	// Only the first push is rejected, so the retry that follows the refresh succeeds.
	sf, attemptsOf := apexServer(t, func(attempt int) int {
		if attempt == 1 {
			return http.StatusUnauthorized
		}
		return http.StatusOK
	})
	defer sf.Close()

	bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokens.URL)
	bridge.oauthCurrentToken = staleToken
	bridge.salesforceURL = sf.URL + "/"

	// Cancelling from inside the poll bounds the run to a single cycle: featureLoop only
	// examines the context once the cycle is over. Both recorded pushes are therefore
	// attempts at the same request, which is what makes comparing their bodies meaningful.
	ld := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		bridge.cancel()
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(flagPayload))
	}))
	defer ld.Close()
	bridge.launchDarklyBaseURI = ld.URL

	if err := bridge.featureLoop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}

	attempts := attemptsOf()
	if len(attempts) != 2 {
		t.Fatalf("Salesforce served %d pushes in one cycle, want 2: the rejected one and the "+
			"retry. A retry whose body was not replayed never arrives at all -- the transport "+
			"refuses to send a request that declared a ContentLength and has nothing left to "+
			"read", len(attempts))
	}
	if !bytes.Equal(attempts[0].body, attempts[1].body) {
		t.Errorf("the retry sent a different body than the first attempt\nfirst: %q\nretry: %q",
			attempts[0].body, attempts[1].body)
	}
	for i, attempt := range attempts {
		if string(attempt.body) != flagPayload {
			t.Errorf("push attempt %d sent %q, want the polled flag data %q",
				i+1, attempt.body, flagPayload)
		}
	}
	if refreshes := refreshCount(); refreshes != 1 {
		t.Errorf("token endpoint called %d times, want 1", refreshes)
	}
}

// TestFeatureLoopCountsARetriedPushAsSuccess is the end-to-end form of the change: a
// refresh has to cost a round trip, not a cycle. featureLoop records the poll's ETag only
// once the push has returned 200, so the next poll sending If-None-Match is the loop itself
// reporting that the cycle completed. Before the retry existed the caller saw the rejection,
// left the ETag unset, and waited out the whole poll interval with the org's flag data
// unchanged.
func TestFeatureLoopCountsARetriedPushAsSuccess(t *testing.T) {
	const etag = "flag-data-v1"

	tokens, _ := tokenServer(t)
	defer tokens.Close()

	// Only the first cycle's push is rejected. Later cycles push cleanly, so anything
	// still missing after the first cycle is the first cycle's own doing.
	sf, _ := apexServer(t, func(attempt int) int {
		if attempt == 1 {
			return http.StatusUnauthorized
		}
		return http.StatusOK
	})
	defer sf.Close()

	bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokens.URL)
	bridge.oauthCurrentToken = staleToken
	bridge.flagPollInterval = time.Millisecond
	bridge.salesforceURL = sf.URL + "/"

	var mu sync.Mutex
	var conditionals []string

	ld := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		conditionals = append(conditionals, r.Header.Get("If-None-Match"))
		polls := len(conditionals)
		mu.Unlock()

		if polls >= 2 {
			bridge.cancel()
		}

		// Flag data with an ETag on every poll, so every cycle reaches the push. A 304
		// would skip it.
		w.Header().Set("ETag", etag)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(flagPayload))
	}))
	defer ld.Close()
	bridge.launchDarklyBaseURI = ld.URL

	if err := bridge.featureLoop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}

	mu.Lock()
	defer mu.Unlock()
	if len(conditionals) < 2 {
		t.Fatalf("LaunchDarkly served %d polls, want at least 2", len(conditionals))
	}
	// The bridge has no ETag to offer on the first poll, which is what makes the second
	// one evidence of something rather than of the header always being present.
	if conditionals[0] != "" {
		t.Errorf("the first poll sent If-None-Match %q, want none", conditionals[0])
	}
	if conditionals[1] != etag {
		t.Errorf("the second poll sent If-None-Match %q, want %q; the refresh cost a whole "+
			"poll cycle rather than one round trip", conditionals[1], etag)
	}
}

// TestFeatureLoopReusesConnectionsWhenTheRefreshFails covers the response that used to be
// abandoned. A rejected token whose refresh then fails transiently is reported as
// recoverable, so featureLoop waits and runs the whole cycle again -- and the rejection was
// left neither drained nor closed, so every cycle spent another connection for as long as
// the token endpoint stayed unwell.
//
// The refresh has to fail for this to show. A rejection whose refresh succeeded used to be
// handed back to the caller, which released it; only the failed-refresh path returned a nil
// response and left the rejection to nobody. Now that neither is handed back,
// requestWithOauth is the only place either can be released.
func TestFeatureLoopReusesConnectionsWhenTheRefreshFails(t *testing.T) {
	const wantPushes = 50

	// A 500 from the token endpoint is transient, so authorizeSalesforce reports it as
	// recoverable and the loop keeps running. A 401 there would be permanent and stop the
	// daemon after one cycle, which is the case that never accumulated anything.
	tokens := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"error":"server_error"}`))
	}))
	defer tokens.Close()

	bridge := bridgeForGrant(t, GRANT_CLIENT_CREDENTIALS, tokens.URL)
	bridge.oauthCurrentToken = staleToken
	bridge.flagPollInterval = time.Millisecond

	// Flag data on every poll so every cycle reaches the push. Without an ETag the loop
	// cannot short-circuit to 304.
	ld := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"flags":{},"segments":{}}`))
	}))
	defer ld.Close()
	bridge.launchDarklyBaseURI = ld.URL

	// The rejection carries a body, which is what goes unreleased.
	handler, servedCount := countingHandler(wantPushes, bridge.cancel,
		func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`[{"errorCode":"INVALID_SESSION_ID"}]`))
		})
	sf, connectionCount := connectionCounter(handler)
	defer sf.Close()
	bridge.salesforceURL = sf.URL + "/"

	if err := bridge.featureLoop(); err != nil {
		t.Fatalf("featureLoop returned unexpected error: %v", err)
	}

	served := servedCount()
	if served < wantPushes {
		t.Fatalf("only %d pushes completed, want at least %d", served, wantPushes)
	}
	if connections := connectionCount(); connections > allowedConnections {
		t.Errorf("opened %d connections for %d rejected flag pushes (allowed %d); the "+
			"rejection is never consumed when the refresh after it fails, so no connection "+
			"can be reused", connections, served, allowedConnections)
	}
}
