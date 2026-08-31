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
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

const (
	LD_BASE_URI   = "https://sdk.launchdarkly.com"
	LD_EVENTS_URI = "https://events.launchdarkly.com"
	OAUTH_URI     = "https://login.salesforce.com/services/oauth2/token"
	// The OAuth flows the bridge can use to authenticate to Salesforce, as accepted by
	// OAUTH_GRANT_TYPE.
	//
	// GRANT_CLIENT_CREDENTIALS is the one to prefer for a new deployment: it needs no
	// certificate to generate or rotate, no username -- the run-as identity is designated
	// on the app in Salesforce -- and it sends no time-bound assertion, so it is
	// indifferent to host clock skew.
	//
	// GRANT_PASSWORD is deprecated. Salesforce disables the username-password flow by
	// default on new orgs and is retiring it, and it requires a security token appended to
	// the password.
	GRANT_JWT_BEARER         = "jwt-bearer"
	GRANT_CLIENT_CREDENTIALS = "client-credentials"
	GRANT_PASSWORD           = "password"
	DEFAULT_POLL_INTERVAL    = 30 * time.Second
	SDK_VERSION              = "1.5.1" // x-release-please-version
	USER_AGENT               = "ApexServerClient/" + SDK_VERSION
	HTTP_TIMEOUT             = 30 * time.Second
	// MIN_FLAG_POLL_INTERVAL is the shortest FLAG_POLL_INTERVAL the bridge honors,
	// matching the minimum polling interval used across LaunchDarkly's server SDKs.
	// A shorter configured value is clamped up to it.
	//
	// This must stay less than or equal to DEFAULT_POLL_INTERVAL. The fallback is
	// range-checked along with everything else, so a minimum above the default would
	// clamp the default itself and make it unreachable.
	//
	// EVENT_POLL_INTERVAL has no counterpart: draining events more often is a
	// legitimate tradeoff against Salesforce API consumption, so its only rule is
	// that the interval be positive.
	MIN_FLAG_POLL_INTERVAL = 30 * time.Second
	// EVENT_POLL_INTERVAL_WARN_THRESHOLD is the point below which a configured
	// EVENT_POLL_INTERVAL earns a warning at startup. It is advisory only -- no floor
	// is enforced, because whether a short interval is affordable depends on the org's
	// edition and license count, which the bridge cannot know.
	//
	// 5s is where the cost stops being incidental against the smallest production
	// allocation. Enterprise and Professional orgs start at 100,000 API calls per 24
	// hours, and a 5s drain spends roughly 17,280 of them, about 17%. Below that the
	// curve steepens fast: 2s is around 43% and 1s around 86% of the same allocation.
	EVENT_POLL_INTERVAL_WARN_THRESHOLD = 5 * time.Second
	// EVENT_PUSH_RETRY_DELAY is how long eventLoop waits between the two attempts it
	// makes at pushing a batch of events to LaunchDarkly. It matches the delay the
	// other LaunchDarkly server SDKs use between the same two attempts.
	//
	// It seeds a Bridge field rather than being read where the push happens, so tests
	// can shorten it. Nothing else changes it, and no environment variable exposes it.
	EVENT_PUSH_RETRY_DELAY = 1 * time.Second
	// MAX_EVENT_PUSH_ATTEMPTS is how many times eventLoop sends one batch of events
	// before it abandons them. Two means the original attempt and one retry, matching
	// the other LaunchDarkly server SDKs.
	MAX_EVENT_PUSH_ATTEMPTS = 2
	// INSTANCE_ID_HEADER is the HTTP header used to identify this bridge instance for
	// estimating server-connection-minutes when polling LaunchDarkly. Its value is a
	// v4 UUID generated once per bridge process and constant for that process's lifetime.
	//
	// See: sdk-specs / SCMP-server-connection-minutes-polling (section 1.1).
	INSTANCE_ID_HEADER = "X-LaunchDarkly-Instance-Id"
	// PAYLOAD_ID_HEADER identifies one batch of events. LaunchDarkly deduplicates on it,
	// so a batch that is sent twice is ingested once. The value is generated per batch
	// and repeated by that batch's retry, which is what makes the retry safe.
	PAYLOAD_ID_HEADER = "X-LaunchDarkly-Payload-ID"
	// SCOPE_HEADER names the LaunchDarkly scope on Salesforce-bound requests, so the
	// org can scope stored flag data and queued events to one of them. It is sent only
	// when LD_SCOPE_KEY is configured, which keeps a bridge that has not opted in
	// indistinguishable from one running an older version.
	SCOPE_HEADER = "LD-Scope-Key"
)

type Bridge struct {
	client                http.Client
	salesforceURL         string
	launchDarklyKey       string
	launchDarklyBaseURI   string
	launchDarklyEventsURI string
	oauthId               string
	oauthSecret           string
	oauthUsername         string
	oauthPassword         string
	oauthCurrentToken     string
	oauthJWTKey           *rsa.PrivateKey
	// oauthGrantType is the resolved OAuth flow, always one of the GRANT_ constants.
	oauthGrantType string
	oauthURI       url.URL
	// instanceID is a v4 UUID generated once per bridge process. It is sent on every
	// LaunchDarkly-bound request (see INSTANCE_ID_HEADER) so the platform can estimate
	// server-connection-minutes for polling clients.
	instanceID string
	// scopeKey scopes this bridge's records within the Salesforce org. A scope is one
	// environment of one project, because LD_SDK_KEY names a single environment, so each
	// project and environment pair sharing an org needs its own value here. Empty means
	// unscoped, matching records that carry no scope. It must agree with the scope key
	// configured on the Apex side or evaluation finds no flag data.
	scopeKey string
	// eventPollInterval is how long eventLoop waits between drains of EventData__c,
	// and flagPollInterval is how long featureLoop waits between flag polls. Both
	// default to DEFAULT_POLL_INTERVAL and are configurable per loop.
	eventPollInterval time.Duration
	flagPollInterval  time.Duration
	// eventPushRetryDelay is how long eventLoop waits before it retries an event
	// push. It always holds EVENT_PUSH_RETRY_DELAY outside of tests.
	eventPushRetryDelay time.Duration
	lock                sync.Mutex
	context             context.Context
	cancel              context.CancelFunc
}

func parseDurationFromEnv(name string, fallback time.Duration) time.Duration {
	raw := os.Getenv(name)
	if raw == "" {
		log.Printf("%s is not set, using the default of %s", name, fallback)
		return fallback
	}

	parsed, err := time.ParseDuration(raw)
	if err != nil {
		log.Printf("%s (%s) failed to parse to a duration, using %s", name, raw, fallback)
		return fallback
	}

	return parsed
}

// tokenEndpointFrom builds an org's token endpoint from its Apex REST URL.
//
// The client credentials grant is only accepted on the org's own domain; the shared
// login host answers "invalid_grant: request not supported on this domain". Since
// SALESFORCE_URL already names the right host, the endpoint is derived from it rather
// than being made the operator's problem to discover.
func tokenEndpointFrom(salesforceURL string) (string, error) {
	parsed, err := url.Parse(salesforceURL)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return "", errors.New("cannot derive a token endpoint from SALESFORCE_URL '" +
			salesforceURL + "'; set OAUTH_URI explicitly")
	}

	return parsed.Scheme + "://" + parsed.Host + "/services/oauth2/token", nil
}

// resolveGrantType decides which OAuth flow to use.
//
// An explicit OAUTH_GRANT_TYPE always wins. When it is unset the flow is inferred from the
// credentials present, which is exactly how the bridge behaved before the variable existed:
// a JWT key means the JWT bearer grant, and its absence means the password grant. That keeps
// every deployment predating this option working untouched.
//
// Inference cannot be extended to the client credentials grant, because its credentials --
// OAUTH_ID and OAUTH_SECRET -- are a subset of the password grant's. Selecting it therefore
// requires saying so, which is the reason the variable exists.
func resolveGrantType(oauthJWTKey string) (string, error) {
	configured := strings.ToLower(strings.TrimSpace(os.Getenv("OAUTH_GRANT_TYPE")))

	if configured == "" {
		if oauthJWTKey != "" {
			return GRANT_JWT_BEARER, nil
		}
		return GRANT_PASSWORD, nil
	}

	switch configured {
	case GRANT_JWT_BEARER, GRANT_CLIENT_CREDENTIALS, GRANT_PASSWORD:
		return configured, nil
	}

	return "", errors.New("OAUTH_GRANT_TYPE '" + configured + "' is not recognized; use " +
		GRANT_JWT_BEARER + ", " + GRANT_CLIENT_CREDENTIALS + " or " + GRANT_PASSWORD)
}

func newBridge() (*Bridge, error) {
	var bridge Bridge

	bridge.launchDarklyKey = os.Getenv("LD_SDK_KEY")
	if bridge.launchDarklyKey == "" {
		return nil, errors.New("LD_SDK_KEY not set")
	}

	bridge.salesforceURL = os.Getenv("SALESFORCE_URL")
	if bridge.salesforceURL == "" {
		return nil, errors.New("SALESFORCE_URL not set")
	}

	bridge.launchDarklyBaseURI = os.Getenv("LD_BASE_URI")
	if bridge.launchDarklyBaseURI == "" {
		bridge.launchDarklyBaseURI = LD_BASE_URI
	}

	bridge.launchDarklyEventsURI = os.Getenv("LD_EVENTS_URI")
	if bridge.launchDarklyEventsURI == "" {
		bridge.launchDarklyEventsURI = LD_EVENTS_URI
	}

	bridge.oauthId = os.Getenv("OAUTH_ID")
	if bridge.oauthId == "" {
		return nil, errors.New("OAUTH_ID not set")
	}

	oauthJWTKey := os.Getenv("OAUTH_JWT_KEY")

	grantType, err := resolveGrantType(oauthJWTKey)
	if err != nil {
		return nil, err
	}
	bridge.oauthGrantType = grantType

	// The token endpoint depends on the grant, so it is resolved after it.
	oauthURIString := os.Getenv("OAUTH_URI")
	if oauthURIString == "" {
		if grantType == GRANT_CLIENT_CREDENTIALS {
			derived, err := tokenEndpointFrom(bridge.salesforceURL)
			if err != nil {
				return nil, err
			}
			oauthURIString = derived
			log.Printf("OAUTH_URI is not set; using %s derived from SALESFORCE_URL, because the "+
				"client credentials grant is not accepted on the shared login host", derived)
		} else {
			oauthURIString = OAUTH_URI
		}
	}

	oauthURI, err := url.Parse(oauthURIString)
	if err != nil {
		return nil, errors.New("OAUTH_URI parse failed")
	}
	bridge.oauthURI = *oauthURI

	// A configured login host cannot work for this grant, and Salesforce's rejection --
	// "request not supported on this domain" -- does not point at the cause.
	if grantType == GRANT_CLIENT_CREDENTIALS {
		host := strings.ToLower(bridge.oauthURI.Host)
		if host == "login.salesforce.com" || host == "test.salesforce.com" {
			log.Printf("OAUTH_URI points at %s, which rejects the client credentials grant; "+
				"use the org's own domain, such as %s", host,
				"https://MyDomainName.my.salesforce.com/services/oauth2/token")
		}
	}
	log.Printf("authenticating to Salesforce with the %s grant", grantType)
	if grantType == GRANT_PASSWORD {
		log.Print("the password grant is deprecated: Salesforce disables it by default on new " +
			"orgs and is retiring it. Prefer " + GRANT_CLIENT_CREDENTIALS + " or " + GRANT_JWT_BEARER)
	}

	// Each grant needs a different subset of the OAUTH_ variables, so they are validated per
	// grant rather than unconditionally. In particular the client credentials grant needs no
	// username: the run-as identity is designated on the app in Salesforce.
	switch grantType {
	case GRANT_JWT_BEARER:
		if oauthJWTKey == "" {
			return nil, errors.New("OAUTH_JWT_KEY not set")
		}
		decodedString, err := base64.StdEncoding.DecodeString(oauthJWTKey)
		if err != nil {
			return nil, errors.New("OAUTH_JWT_KEY is not valid standard-encoding base64")
		}
		pem, _ := pem.Decode(decodedString)
		if pem == nil {
			return nil, errors.New("OAUTH_JWT_KEY is not a valid PEM-encoded block")
		}
		if pem.Type != "RSA PRIVATE KEY" {
			return nil, errors.New("OAUTH_JWT_KEY PEM block must be called 'RSA PRIVATE KEY'")
		}
		decodedX509, err := x509.ParsePKCS1PrivateKey(pem.Bytes)
		if err != nil {
			return nil, errors.New("OAUTH_JWT_KEY failed to decode PKCS1 private key from PEM bytes")
		}
		bridge.oauthJWTKey = decodedX509

		bridge.oauthUsername = os.Getenv("OAUTH_USERNAME")
		if bridge.oauthUsername == "" {
			return nil, errors.New("OAUTH_USERNAME not set")
		}
	case GRANT_CLIENT_CREDENTIALS:
		bridge.oauthSecret = os.Getenv("OAUTH_SECRET")
		if bridge.oauthSecret == "" {
			return nil, errors.New("OAUTH_SECRET not set")
		}
	case GRANT_PASSWORD:
		bridge.oauthPassword = os.Getenv("OAUTH_PASSWORD")
		if bridge.oauthPassword == "" {
			return nil, errors.New("OAUTH_PASSWORD not set")
		}
		bridge.oauthSecret = os.Getenv("OAUTH_SECRET")
		if bridge.oauthSecret == "" {
			return nil, errors.New("OAUTH_SECRET not set")
		}

		bridge.oauthUsername = os.Getenv("OAUTH_USERNAME")
		if bridge.oauthUsername == "" {
			return nil, errors.New("OAUTH_USERNAME not set")
		}
	}

	httpTimeoutDuration := HTTP_TIMEOUT
	httpTimeout := os.Getenv("HTTP_TIMEOUT")
	if httpTimeout != "" {
		httpTimeout, err := time.ParseDuration(httpTimeout)
		if err != nil {
			return nil, errors.New("HTTP_TIMEOUT parse failed")
		}
		if httpTimeout < 0 {
			return nil, errors.New("HTTP_TIMEOUT must be >= 0")
		}
		httpTimeoutDuration = httpTimeout
	}

	bridge.eventPollInterval = parseDurationFromEnv("EVENT_POLL_INTERVAL", DEFAULT_POLL_INTERVAL)
	if bridge.eventPollInterval <= 0 {
		log.Printf("%s duration (%s) is non-positive, using %s", "EVENT_POLL_INTERVAL", bridge.eventPollInterval, DEFAULT_POLL_INTERVAL)
		bridge.eventPollInterval = DEFAULT_POLL_INTERVAL
	}

	if bridge.eventPollInterval < EVENT_POLL_INTERVAL_WARN_THRESHOLD {
		log.Printf("%s duration (%s) is below %s, polling may trigger organization wide API limits",
			"EVENT_POLL_INTERVAL", bridge.eventPollInterval, EVENT_POLL_INTERVAL_WARN_THRESHOLD)
	}

	bridge.flagPollInterval = parseDurationFromEnv("FLAG_POLL_INTERVAL", DEFAULT_POLL_INTERVAL)
	if bridge.flagPollInterval < MIN_FLAG_POLL_INTERVAL {
		log.Printf("%s duration (%s) is less than the minimum of %s, using %s", "FLAG_POLL_INTERVAL", bridge.flagPollInterval, MIN_FLAG_POLL_INTERVAL, MIN_FLAG_POLL_INTERVAL)
		bridge.flagPollInterval = MIN_FLAG_POLL_INTERVAL
	}

	bridge.eventPushRetryDelay = EVENT_PUSH_RETRY_DELAY

	bridge.client = http.Client{
		Timeout: httpTimeoutDuration,
	}

	// Optional. Unset means this bridge owns the records that carry no scope, which is
	// both the behavior from before scoping and the state an existing deployment upgrades
	// into without changing anything. Logged either way, because a mismatch against the
	// Apex-side scope key produces no error -- evaluation simply finds no flag data and
	// every variation returns its fallback.
	bridge.scopeKey = strings.TrimSpace(os.Getenv("LD_SCOPE_KEY"))
	if bridge.scopeKey == "" {
		log.Print("LD_SCOPE_KEY is not set, scoping to records with no scope")
	} else {
		log.Printf("LD_SCOPE_KEY is %q; the Apex client must be configured with the same value",
			bridge.scopeKey)
	}

	context, cancel := context.WithCancel(context.Background())
	bridge.context = context
	bridge.cancel = cancel

	// Generate a stable v4 UUID once per bridge instance. This identifier travels on
	// every LaunchDarkly-bound request via INSTANCE_ID_HEADER for the lifetime of the
	// process, per the SCMP-server-connection-minutes-polling spec.
	bridge.instanceID = uuid.New().String()

	return &bridge, nil
}

type AuthBody struct {
	AccessToken string `json:"access_token"`
}

type JWTClaim struct {
	ISS string `json:"iss"`
	Sub string `json:"sub"`
	Aud string `json:"aud"`
	Exp string `json:"exp"`
}

func (bridge *Bridge) makeJWT() (*string, error) {
	var claim JWTClaim

	claim.ISS = bridge.oauthId
	claim.Sub = bridge.oauthUsername
	claim.Aud = bridge.oauthURI.Host
	claim.Exp = strconv.FormatInt(time.Now().Unix()+(60*2), 10)

	bytesClaim, err := json.Marshal(claim)
	if err != nil {
		return nil, err
	}
	base64Header := base64.URLEncoding.EncodeToString([]byte("{\"alg\":\"RS256\"}"))
	base64Claim := base64.URLEncoding.EncodeToString(bytesClaim)
	jwt := base64Header + "." + base64Claim

	hasher := sha256.New()
	hasher.Write([]byte(jwt))
	digest := hasher.Sum(nil)

	signature, err := rsa.SignPKCS1v15(rand.Reader, bridge.oauthJWTKey, crypto.SHA256, digest)
	if err != nil {
		return nil, err
	}
	base64Signature := base64.URLEncoding.EncodeToString(signature)
	jwt += "." + base64Signature

	return &jwt, nil
}

func (bridge *Bridge) authorizeSalesforce() (error, bool) {
	query := url.Values{}
	switch bridge.oauthGrantType {
	case GRANT_JWT_BEARER:
		jwt, err := bridge.makeJWT()
		if err != nil {
			return err, true
		}
		query.Add("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
		query.Add("assertion", *jwt)
	case GRANT_CLIENT_CREDENTIALS:
		// No username: the app in Salesforce designates the run-as identity, so the
		// daemon holds no user credential at all.
		query.Add("grant_type", "client_credentials")
		query.Add("client_id", bridge.oauthId)
		query.Add("client_secret", bridge.oauthSecret)
	case GRANT_PASSWORD:
		query.Add("grant_type", "password")
		query.Add("client_id", bridge.oauthId)
		query.Add("client_secret", bridge.oauthSecret)
		query.Add("username", bridge.oauthUsername)
		query.Add("password", bridge.oauthPassword)
	default:
		// newBridge resolves the grant to one of the constants above and refuses to start
		// otherwise, so reaching here means the two have drifted apart.
		return errors.New("unsupported OAuth grant type '" + bridge.oauthGrantType + "'"), true
	}

	authRequest, err := http.NewRequest("POST", bridge.oauthURI.String(), strings.NewReader(query.Encode()))
	if err != nil {
		return err, true
	}

	authRequest.Header.Add("Content-Type", "application/x-www-form-urlencoded")

	authResponse, err := bridge.client.Do(authRequest)
	if err != nil {
		return err, false
	}
	// readErr is named apart from err because which error is in hand matters below. The
	// status line arrives ahead of the body, so net/http hands back a complete StatusCode
	// whether or not the body read finished. That makes the read error irrelevant to some
	// of the branches below and decisive in others, so each one judges it for itself
	// rather than one check up front settling it for all three.
	errorBody, readErr := ioutil.ReadAll(authResponse.Body)
	authResponse.Body.Close()

	// A 401 or 403 is Salesforce rejecting the credential, and it rejects the same
	// credential on every retry. The status code alone establishes that, so the failure
	// stays permanent even when the body arrives short. Here the body is a log detail and
	// nothing more, which makes the log line the only record of readErr. Returning readErr
	// instead would be the worse bug: the caller reads a non-permanent error as worth
	// retrying, so the daemon would spin forever against a credential that cannot work.
	if authResponse.StatusCode == 401 || authResponse.StatusCode == 403 {
		log.Print("Salesforce permanent auth failure: ", authResponse.StatusCode, string(errorBody), readErr)
		return errors.New("Salesforce Unauthorized"), true
	}

	// Every other non-200 turns the body into the error message, so a short read has to be
	// reported rather than quietly truncating what the caller logs. The status code goes in
	// the message either way. A token endpoint can answer with no body at all -- a 503 from
	// a load balancer in front of Salesforce does -- and errors.New on an empty body yields
	// an error that prints nothing.
	if authResponse.StatusCode != 200 {
		log.Print("Salesforce auth failure: ", authResponse.StatusCode, string(errorBody), readErr)
		if readErr != nil {
			// Wrapped rather than returned bare, so the status code reaches the
			// operator on this path as well. The caller only logs this error, and
			// "unexpected EOF" on its own does not say what failed.
			return fmt.Errorf("Salesforce auth failure, status %d, response body read failed: %w",
				authResponse.StatusCode, readErr), false
		}
		return errors.New("Salesforce auth failure, status " +
			strconv.Itoa(authResponse.StatusCode) + ": " + string(errorBody)), false
	}

	// A 200 whose body did not arrive in full cannot be trusted to hold the whole token
	// document, so the read error decides this branch. Retrying is right: Salesforce
	// accepted the credential, and only the transfer failed.
	if readErr != nil {
		return readErr, false
	}

	var parsed AuthBody
	json.Unmarshal(errorBody, &parsed)
	if parsed.AccessToken == "" {
		return errors.New("expected access token in body"), false
	}

	bridge.lock.Lock()
	defer bridge.lock.Unlock()
	bridge.oauthCurrentToken = parsed.AccessToken

	return nil, false
}

// drainAndClose finishes with a response whose body the caller does not need.
//
// Both halves matter. Closing releases the connection's file descriptor, and draining
// is what lets the transport put the connection back in its pool: a body that never
// reaches EOF leaves the connection unusable, so the next request has to dial a new
// one. Draining copies to ioutil.Discard rather than reading into a buffer, so an
// oversized error body costs bandwidth but is never held in memory.
//
// StatusCode and Header remain readable afterwards, so a caller can finish with a
// response before inspecting it.
func drainAndClose(response *http.Response) {
	_, _ = io.Copy(ioutil.Discard, response.Body)
	_ = response.Body.Close()
}

// sendWithToken stamps the current OAuth token on a request and sends it.
//
// It is a separate function because requestWithOauth can send the same request twice,
// and everything here has to happen again on the second attempt. The token is re-read
// from the bridge each time, so a second attempt carries what authorizeSalesforce just
// stored rather than the value that was refused.
//
// The body is replayed from GetBody, because the transport consumes and closes it while
// writing the request. Leaving that out fails intermittently rather than consistently,
// which is worse than failing outright: the transport sees a request that declared a
// ContentLength and then wrote no body, and if the attempt went out on a pooled connection
// it rewinds through GetBody and retries itself, so the bug stays invisible. That cover
// disappears as soon as the retry has to dial -- because the org closed the connection, or
// the pool reaped it while idle -- and the send fails with "ContentLength=N with Body
// length 0" instead.
//
// http.NewRequest supplies a GetBody for every body the bridge builds, and leaves it nil
// when the request carries no body at all, which is the case for both poll requests.
// Replaying on the first attempt swaps an unread body for an equivalent unread body, so
// the rule can live here, at the send, rather than only on the path that needs it.
func (bridge *Bridge) sendWithToken(request *http.Request) (*http.Response, error) {
	bridge.lock.Lock()
	token := bridge.oauthCurrentToken
	bridge.lock.Unlock()

	request.Header.Set("Authorization", "Bearer "+token)

	// Every Salesforce-bound request goes through this function, so the scope is stamped
	// here rather than at each call site. When unset the header is omitted entirely, so the
	// request is indistinguishable from one sent by a bridge predating scope
	// support -- which is what makes either upgrade order safe.
	if bridge.scopeKey != "" {
		request.Header.Set(SCOPE_HEADER, bridge.scopeKey)
	}

	if request.GetBody != nil {
		body, err := request.GetBody()
		if err != nil {
			return nil, err
		}
		request.Body = body
	}

	return bridge.client.Do(request)
}

// requestWithOauth sends a Salesforce-bound request, and on a rejected token refreshes
// it and sends the request a second time.
//
// The second attempt is what makes a token expiry cheap. Salesforce ends a session on
// its own schedule, so the bridge only learns its token is dead by having a request
// refused. Refreshing alone leaves the new token unused until the next cycle, and the
// caller has already treated this one as failed -- so a routine expiry costs a whole
// poll interval of stale flag data or undelivered events. Sending again costs one round
// trip instead.
//
// One retry, never more. A token minted seconds ago being refused is not an expiry, so
// refreshing again cannot change the answer: it means the connected app's permissions or
// its run-as identity changed. That response is handed back as it stands, so the loop logs it
// and waits, instead of spending the org's API allocation on a rejection that repeats.
//
// The caller owns the returned response and must finish with it. Every response this
// function does not return is drained and closed here, so nothing keeps holding a
// connection and nothing is closed twice.
func (bridge *Bridge) requestWithOauth(request *http.Request) (*http.Response, error, bool) {
	response, err := bridge.sendWithToken(request)
	if err != nil {
		return nil, err, false
	}

	if response.StatusCode != 401 && response.StatusCode != 403 {
		return response, nil, false
	}

	// No path below returns this response or reads its body, so finish with it here.
	// Draining before authorizing also returns the connection to the pool in time for the
	// token request to reuse it.
	drainAndClose(response)

	err, permanent := bridge.authorizeSalesforce()
	if err != nil {
		return nil, err, permanent
	}

	response, err = bridge.sendWithToken(request)
	if err != nil {
		return nil, err, false
	}

	return response, nil, false
}

func (bridge *Bridge) eventLoop() error {
	pollURI := bridge.salesforceURL + "event"
	pushURI := bridge.launchDarklyEventsURI + "/bulk"

	for {
		pollRequest, err := http.NewRequest("GET", pollURI, nil)
		if err != nil {
			return err
		}

		pollRequest.Header.Set("Content-Type", "application/json")

		log.Print("requesting events from: " + pollURI)
		pollResponse, err, permanent := bridge.requestWithOauth(pollRequest)
		if permanent {
			return errors.New("Requesting events from Salesforce OAuth failure")
		}

		if err != nil {
			log.Print("poll events failed")

			goto End
		} else {
			if pollResponse.StatusCode != 200 {
				// Nothing below needs the body, so stream it away instead of
				// allocating it.
				drainAndClose(pollResponse)
				log.Print("poll events expected 200 but got ", pollResponse.StatusCode)
				goto End
			}

			pollBytes, readErr := ioutil.ReadAll(pollResponse.Body)
			pollResponse.Body.Close()
			if readErr != nil {
				log.Print("failed to read poll events response body")
				goto End
			}

			if bytes.Equal(pollBytes, []byte("[]")) {
				log.Print("No new events skipping delivery")
				goto End
			}

			// The push gets two attempts a second apart, which is what the other
			// LaunchDarkly server SDKs give it. Most push failures are transient -- a
			// dropped connection, a rate limit, one unhealthy node answering 503 -- and
			// a second attempt clears them inside this cycle rather than after a whole
			// poll interval.
			//
			// Two attempts is the entire budget, and it does not make delivery durable.
			// Salesforce deletes the events as it hands them over, so a batch that fails
			// both attempts is gone. The retry only makes that outcome less frequent.
			// Generated per batch rather than per attempt, and deliberately outside
			// the loop below. A retry that carried a fresh id would look like a new
			// batch to LaunchDarkly, so the events would be counted twice.
			//
			// That matters for the one failure a retry cannot see: an attempt the
			// service accepted whose response never reached the bridge. The retry
			// cannot tell that from an attempt nobody received, so it sends again
			// either way, and this header is what keeps the first outcome from
			// double-counting. It mirrors the reference Go SDK's event sender.
			payloadID := uuid.New().String()

			for attempt := 1; attempt <= MAX_EVENT_PUSH_ATTEMPTS; attempt++ {
				if attempt > 1 {
					log.Print("retrying the event push in: ", bridge.eventPushRetryDelay)

					// The delay watches the context as well as the clock, so a shutdown
					// during it stops the daemon at once instead of after the delay.
					// Shutdown abandons the retry rather than making one more attempt:
					// the process is on its way out.
					select {
					case <-bridge.context.Done():
						return nil
					case <-time.After(bridge.eventPushRetryDelay):
					}
				}

				// Each attempt builds its own request. client.Do reads the body to the
				// end, so sending one request twice would send the events once and an
				// empty body after that.
				pushRequest, err := http.NewRequest("POST", pushURI, bytes.NewReader(pollBytes))
				if err != nil {
					return err
				}

				pushRequest.Header.Set("Content-Type", "application/json")
				pushRequest.Header.Set("X-LaunchDarkly-Event-Schema", "3")
				pushRequest.Header.Set("Authorization", bridge.launchDarklyKey)
				pushRequest.Header.Set("User-Agent", USER_AGENT)
				// Sent on every LaunchDarkly-bound request (matches the reference Go SDK,
				// where DefaultHeaders carries the instance id across poll/stream/events).
				pushRequest.Header.Set(INSTANCE_ID_HEADER, bridge.instanceID)
				pushRequest.Header.Set(PAYLOAD_ID_HEADER, payloadID)

				log.Print("pushing events to: " + pushURI)

				pushResponse, err := bridge.client.Do(pushRequest)
				if err != nil {
					// A failure below the HTTP layer says nothing about the request, so
					// another attempt is always worth making. Only the attempt budget
					// decides the outcome here.
					log.Print("failed pushing events to LaunchDarkly: ", err,
						", ", pushDisposition(attempt, true))
					continue
				}
				// Only the status matters here, so the body is discarded rather than read.
				drainAndClose(pushResponse)

				// A retry cannot make a rejected SDK key acceptable, so an attempt spent
				// on one is wasted. The daemon stops instead, because the same key
				// authorizes every other LaunchDarkly request it makes.
				if pushResponse.StatusCode == 401 || pushResponse.StatusCode == 403 {
					return errors.New("Pushing events to LaunchDarkly unauthorized")
				}

				if pushResponse.StatusCode == 200 || pushResponse.StatusCode == 202 {
					break
				}

				recoverable := isHTTPErrorRecoverable(pushResponse.StatusCode)

				log.Print("event push expected 200/202 got: ", pushResponse.StatusCode,
					", ", pushDisposition(attempt, recoverable))

				// A status that reports something wrong with the request gets no retry.
				// The next attempt would send the same bytes to the same place.
				if !recoverable {
					break
				}
			}
		}

	End:
		log.Print("event polling waiting for: ", bridge.eventPollInterval)

		select {
		case <-bridge.context.Done():
			return nil
		case <-time.After(bridge.eventPollInterval):
		}
	}
}

// pushDisposition says what becomes of a batch after a failed push attempt, so every
// failure the bridge logs also reports whether the events still have a chance. The
// other LaunchDarkly SDKs annotate their event push failures the same way, and without
// it a reader cannot tell a first failure from a final one -- the two lines are
// otherwise identical.
//
// A lost batch is named as lost, because nothing sends it again. Salesforce deleted the
// events as it handed them over, so no later cycle retries them.
//
// attempt counts from 1, matching the loop that calls this.
func pushDisposition(attempt int, recoverable bool) string {
	if !recoverable {
		return "not retryable, this batch is lost"
	}

	if attempt < MAX_EVENT_PUSH_ATTEMPTS {
		return "will retry"
	}

	return "out of attempts, this batch is lost"
}

// isHTTPErrorRecoverable reports whether an HTTP error status might answer
// differently if the same request is sent again. It matches the function of the same
// name in go-sdk-events, so the bridge gives up on the statuses the other
// LaunchDarkly server SDKs give up on.
//
// Among the 4xx statuses only 400, 408 and 429 are recoverable. A request timeout and
// a rate limit both clear on their own, and LaunchDarkly's SDKs treat 400 as
// recoverable as well. Every other 4xx reports something wrong with the request
// itself, which repeating it verbatim cannot change.
//
// Everything outside 4xx is recoverable. That covers 5xx and any status the service
// has not returned before, so an unexpected one costs a retry rather than a batch.
func isHTTPErrorRecoverable(statusCode int) bool {
	if statusCode >= 400 && statusCode < 500 {
		switch statusCode {
		case 400, 408, 429:
			return true
		default:
			return false
		}
	}

	return true
}

func (bridge *Bridge) featureLoop() error {
	etag := ""

	pollURI := bridge.launchDarklyBaseURI + "/sdk/latest-all"

	for {
		pollRequest, err := http.NewRequest("GET", pollURI, nil)
		if err != nil {
			return err
		}

		pollRequest.Header.Set("Authorization", bridge.launchDarklyKey)
		pollRequest.Header.Set("User-Agent", USER_AGENT)
		pollRequest.Header.Set(INSTANCE_ID_HEADER, bridge.instanceID)

		if etag != "" {
			pollRequest.Header.Set("If-None-Match", etag)
		}

		log.Print("requesting flags from: " + pollURI)

		pollResponse, err := bridge.client.Do(pollRequest)

		if err != nil {
			log.Print("poll flags failed: ", err)

			goto End
		} else {
			if pollResponse.StatusCode != 200 {
				// None of the cases below need the body -- a 304 does not even carry
				// one -- so stream it away instead of allocating it.
				drainAndClose(pollResponse)

				if pollResponse.StatusCode == 401 || pollResponse.StatusCode == 403 {
					return errors.New("requesting flags unauthorized")
				}

				if pollResponse.StatusCode == 304 {
					log.Print("poll flags received 304 skipping update")
					goto End
				}

				log.Print("poll flags expected 200, got ", pollResponse.StatusCode)
				goto End
			}

			etag = ""

			pollBytes, readErr := ioutil.ReadAll(pollResponse.Body)
			pollResponse.Body.Close()
			if readErr != nil {
				log.Print("failed to read flag poll response body")
				goto End
			}

			pushURI := bridge.salesforceURL + "store"
			// A bytes.Reader rather than a bytes.Buffer, because requestWithOauth can send
			// this request a second time after refreshing the token. Both give
			// http.NewRequest enough to build a GetBody, so both replay as the code stands,
			// but only the Reader is a read-only view of pollBytes. A Buffer is a writable
			// staging area that http.NewRequest snapshots once, so a later write to it would
			// leave the two attempts sending different bytes.
			pushRequest, err := http.NewRequest("POST", pushURI, bytes.NewReader(pollBytes))
			if err != nil {
				log.Print("failed constructing flag push request ", err)
				return errors.New("Failed constructiong flag push request")
			}
			pushRequest.Header.Set("Content-Type", "application/json")

			log.Print("pushing flags to: " + pushURI)
			pushResponse, err, permanent := bridge.requestWithOauth(pushRequest)
			if permanent {
				return errors.New("Feature push Salesforce OAuth failure")
			}
			if err != nil {
				etag = ""
				log.Print("failed pushings flags to salesforce: ", err)
				goto End
			}
			// Only the status matters here, so the body is discarded rather than read.
			drainAndClose(pushResponse)

			if pushResponse.StatusCode != 200 {
				log.Print("push flags expected 200 got ", pushResponse.StatusCode)
				goto End
			}

			etag = pollResponse.Header.Get("ETag")
		}

	End:
		log.Print("feature polling waiting for: ", bridge.flagPollInterval)

		select {
		case <-bridge.context.Done():
			return nil
		case <-time.After(bridge.flagPollInterval):
		}
	}
}

func (bridge *Bridge) run() error {
	err, _ := bridge.authorizeSalesforce()
	if err != nil {
		return err
	}

	c := make(chan error)
	go func() {
		c <- bridge.eventLoop()
		bridge.cancel()
	}()
	go func() {
		c <- bridge.featureLoop()
		bridge.cancel()
	}()

	err1 := <-c
	err2 := <-c

	if err1 != nil {
		return err1
	}

	return err2
}

func main() {
	bridge, err := newBridge()
	if err != nil {
		log.Fatal("Error creating bridge: ", err)
	}

	err = bridge.run()
	if err != nil {
		log.Fatal("Error running bridge: ", err)
	}
}
