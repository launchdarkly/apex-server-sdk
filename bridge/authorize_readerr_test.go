package main

import (
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
)

// The tests in this file all pin one flow rather than ranging over allGrants.
// TestAuthorizeSalesforceHandlesTokenResponses already establishes that response handling
// is identical across the three, and the reason holds here: the grant only shapes the
// request body, and every line under test runs after client.Do returns. Ranging would
// triple the subtests without adding a failure any of them could catch on its own.
const readErrGrant = GRANT_CLIENT_CREDENTIALS

// truncatingTokenServer starts a token endpoint that fails its body mid-read.
//
// The handler promises more bytes in Content-Length than it writes. Go's server notices
// the shortfall when the handler returns and closes the connection without finishing the
// body, so the client's ReadAll ends in io.ErrUnexpectedEOF while still returning the
// bytes that did arrive. That is the shape authorizeSalesforce has to cope with: the
// status line lands intact, and only the body is cut short.
func truncatingTokenServer(t *testing.T, status int, body string) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", strconv.Itoa(len(body)+64))
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(server.Close)

	return server
}

// TestAuthorizeSalesforceClassifiesAFailedBodyRead covers a token response whose body
// fails part way through, one status class at a time. The classes are handled differently
// because the body means something different in each: a log detail on 401 and 403, the
// error message on any other non-200, and the token document on 200.
//
// The permanent flag is the assertion that matters. Permanent stops the daemon, and
// non-permanent retries, so misclassifying a rejected credential leaves the bridge
// hammering the token endpoint with a credential Salesforce will never accept. Hoisting
// the read-error check above the status branches is the tempting tidy-up and introduces
// exactly that regression; the 401 and 403 rows are what catch it.
func TestAuthorizeSalesforceClassifiesAFailedBodyRead(t *testing.T) {
	const existingToken = "token-from-an-earlier-authorization"

	tests := []struct {
		name string
		// status is what the endpoint answers with. body is the partial payload that
		// reaches the client before the connection closes.
		status        int
		body          string
		wantPermanent bool
		// wantReadErr requires authorizeSalesforce to hand the read failure back, which
		// is only right where the body is load-bearing.
		wantReadErr bool
		// wantMessage is the exact error text, asserted where the function is supposed
		// to report the status class rather than the read failure.
		wantMessage string
	}{
		// The credential is rejected whether or not the body arrived, so the read failure
		// changes nothing. It is logged and deliberately not returned.
		{
			name:          "401 stays permanent",
			status:        401,
			body:          `{"error":"invalid_cli`,
			wantPermanent: true,
			wantMessage:   "Salesforce Unauthorized",
		},
		{
			name:          "403 stays permanent",
			status:        403,
			body:          `{"error":"forbid`,
			wantPermanent: true,
			wantMessage:   "Salesforce Unauthorized",
		},

		// Here the body would have become the error message. A half-received message must
		// not stand in for the failure, so the read error is reported instead.
		{name: "500 reports the read error", status: 500, body: "upstream fail", wantReadErr: true},

		// A 200 body is the token document. This one already parses, which is the point:
		// the bytes that arrived are not evidence the rest did, so the token must not be
		// stored on the strength of a truncated response.
		{
			name:        "200 reports the read error",
			status:      200,
			body:        `{"access_token":"issued-token"}`,
			wantReadErr: true,
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			tokenServer := truncatingTokenServer(t, test.status, test.body)

			bridge := bridgeForGrant(t, readErrGrant, tokenServer.URL)
			bridge.oauthCurrentToken = existingToken

			err, permanent := bridge.authorizeSalesforce()
			if err == nil {
				t.Fatal("authorizeSalesforce succeeded on a truncated response, want an error")
			}
			if permanent != test.wantPermanent {
				t.Errorf("permanent = %v, want %v", permanent, test.wantPermanent)
			}
			// Every case here is a failure, so the token in hand has to survive it. A
			// transient failure that clears the token would deauthorize a running bridge.
			if bridge.oauthCurrentToken != existingToken {
				t.Errorf("token = %q, want it left as %q", bridge.oauthCurrentToken, existingToken)
			}
			if test.wantReadErr && !errors.Is(err, io.ErrUnexpectedEOF) {
				t.Errorf("error = %v, want the read failure wrapping io.ErrUnexpectedEOF", err)
			}
			if !test.wantReadErr && errors.Is(err, io.ErrUnexpectedEOF) {
				t.Errorf("error = %v, want the status classification rather than the read failure", err)
			}
			if test.wantMessage != "" && err.Error() != test.wantMessage {
				t.Errorf("error = %q, want %q", err.Error(), test.wantMessage)
			}
		})
	}
}

// TestAuthorizeSalesforceNamesTheStatusInATransientFailure covers the message the generic
// non-200 branch builds. That branch used to return errors.New on the response body alone,
// which prints nothing at all when the body is empty -- and a token endpoint answering 503
// with no body is ordinary, not exotic. The caller logs this error and has nothing else to
// go on, so an empty message costs the operator the whole diagnosis.
//
// TestAuthorizeSalesforceHandlesTokenResponses covers the same statuses but only asserts
// that an error came back, and errors.New("") satisfies that. This is the test that fails
// on a blank message.
func TestAuthorizeSalesforceNamesTheStatusInATransientFailure(t *testing.T) {
	tests := []struct {
		name   string
		status int
		body   string
		// wantContains is checked as a substring so the wording stays free to change
		// while the facts the message has to carry do not.
		wantContains []string
	}{
		// The status code is the whole diagnosis when there is no body to report.
		{name: "503 with no body", status: 503, wantContains: []string{"503"}},
		// With a body, the status is added and the body is still reported in full.
		// Salesforce explains a refused grant only in the body.
		{
			name:         "400 with a body",
			status:       400,
			body:         `{"error":"invalid_grant","error_description":"request not supported on this domain"}`,
			wantContains: []string{"400", "invalid_grant", "request not supported on this domain"},
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(test.status)
				_, _ = w.Write([]byte(test.body))
			}))
			defer tokenServer.Close()

			bridge := bridgeForGrant(t, readErrGrant, tokenServer.URL)

			err, permanent := bridge.authorizeSalesforce()
			if err == nil {
				t.Fatalf("authorizeSalesforce succeeded on a %d, want an error", test.status)
			}
			if permanent {
				t.Errorf("a %d was classified as permanent, want it retried", test.status)
			}
			if err.Error() == "" {
				t.Fatal("authorizeSalesforce returned an error with an empty message")
			}
			for _, want := range test.wantContains {
				if !strings.Contains(err.Error(), want) {
					t.Errorf("error = %q, want it to mention %q", err.Error(), want)
				}
			}
		})
	}
}
