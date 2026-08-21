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
	LD_BASE_URI           = "https://sdk.launchdarkly.com"
	LD_EVENTS_URI         = "https://events.launchdarkly.com"
	OAUTH_URI             = "https://login.salesforce.com/services/oauth2/token"
	DEFAULT_POLL_INTERVAL = 30 * time.Second
	SDK_VERSION           = "1.5.1" // x-release-please-version
	USER_AGENT            = "ApexServerClient/" + SDK_VERSION
	HTTP_TIMEOUT          = 30 * time.Second
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
	// INSTANCE_ID_HEADER is the HTTP header used to identify this bridge instance for
	// estimating server-connection-minutes when polling LaunchDarkly. Its value is a
	// v4 UUID generated once per bridge process and constant for that process's lifetime.
	//
	// See: sdk-specs / SCMP-server-connection-minutes-polling (section 1.1).
	INSTANCE_ID_HEADER = "X-LaunchDarkly-Instance-Id"
	// PROJECT_HEADER names the LaunchDarkly project on Salesforce-bound requests, so the
	// org can scope stored flag data and queued events to one project. It is sent only
	// when LD_PROJECT_KEY is configured, which keeps a bridge that has not opted in
	// indistinguishable from one running an older version.
	PROJECT_HEADER = "LD-Project-Key"
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
	oauthURI              url.URL
	// instanceID is a v4 UUID generated once per bridge process. It is sent on every
	// LaunchDarkly-bound request (see INSTANCE_ID_HEADER) so the platform can estimate
	// server-connection-minutes for polling clients.
	instanceID string
	// projectKey scopes this bridge to one LaunchDarkly project within the Salesforce org.
	// Empty means unscoped, matching records that carry no project. It must agree with the
	// project key configured on the Apex side or evaluation finds no flag data.
	projectKey string
	// eventPollInterval is how long eventLoop waits between drains of EventData__c,
	// and flagPollInterval is how long featureLoop waits between flag polls. Both
	// default to DEFAULT_POLL_INTERVAL and are configurable per loop.
	eventPollInterval time.Duration
	flagPollInterval  time.Duration
	lock              sync.Mutex
	context           context.Context
	cancel            context.CancelFunc
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

	oauthURIString := os.Getenv("OAUTH_URI")
	if oauthURIString == "" {
		oauthURIString = OAUTH_URI
	}

	oauthURI, err := url.Parse(oauthURIString)
	if err != nil {
		return nil, errors.New("OAUTH_URI parse failed")
	}
	bridge.oauthURI = *oauthURI

	oauthJWTKey := os.Getenv("OAUTH_JWT_KEY")
	if oauthJWTKey == "" {
		bridge.oauthPassword = os.Getenv("OAUTH_PASSWORD")
		if bridge.oauthPassword == "" {
			return nil, errors.New("OAUTH_PASSWORD not set")
		}
		bridge.oauthSecret = os.Getenv("OAUTH_SECRET")
		if bridge.oauthSecret == "" {
			return nil, errors.New("OAUTH_SECRET not set")
		}
	} else {
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
	}

	bridge.oauthUsername = os.Getenv("OAUTH_USERNAME")
	if bridge.oauthUsername == "" {
		return nil, errors.New("OAUTH_USERNAME not set")
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
		log.Printf("event flush interval is %s, polling may trigger organization wide API limits",
			bridge.eventPollInterval)
	}

	bridge.flagPollInterval = parseDurationFromEnv("FLAG_POLL_INTERVAL", DEFAULT_POLL_INTERVAL)
	if bridge.flagPollInterval < MIN_FLAG_POLL_INTERVAL {
		log.Printf("%s duration (%s) is less than the minimum of %s, using %s", "FLAG_POLL_INTERVAL", bridge.flagPollInterval, MIN_FLAG_POLL_INTERVAL, MIN_FLAG_POLL_INTERVAL)
		bridge.flagPollInterval = MIN_FLAG_POLL_INTERVAL
	}

	bridge.client = http.Client{
		Timeout: httpTimeoutDuration,
	}

	// Optional. Unset means this bridge owns the records that carry no project, which is
	// both the pre-multi-project behavior and the state an existing deployment upgrades
	// into without changing anything. Logged either way, because a mismatch against the
	// Apex-side project key produces no error -- evaluation simply finds no flag data and
	// every variation returns its fallback.
	bridge.projectKey = strings.TrimSpace(os.Getenv("LD_PROJECT_KEY"))
	if bridge.projectKey == "" {
		log.Print("LD_PROJECT_KEY is not set, scoping to records with no project")
	} else {
		log.Printf("LD_PROJECT_KEY is %q; the Apex client must be configured with the same value",
			bridge.projectKey)
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
	if bridge.oauthJWTKey != nil {
		jwt, err := bridge.makeJWT()
		if err != nil {
			return err, true
		}
		query.Add("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
		query.Add("assertion", *jwt)
	} else {
		query.Add("grant_type", "password")
		query.Add("client_id", bridge.oauthId)
		query.Add("client_secret", bridge.oauthSecret)
		query.Add("username", bridge.oauthUsername)
		query.Add("password", bridge.oauthPassword)
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
	errorBody, err := ioutil.ReadAll(authResponse.Body)
	authResponse.Body.Close()

	if authResponse.StatusCode == 401 || authResponse.StatusCode == 403 {
		log.Print("Salesforce permanent auth failure: ", authResponse.StatusCode, string(errorBody), err)
		return errors.New("Salesforce Unauthorized"), true
	}

	if authResponse.StatusCode != 200 {
		log.Print("Salesforce auth failure: ", authResponse.StatusCode, string(errorBody), err)
		return errors.New(string(errorBody)), false
	}

	if err != nil {
		return err, false
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

func (bridge *Bridge) requestWithOauth(request *http.Request) (*http.Response, error, bool) {
	bridge.lock.Lock()
	token := bridge.oauthCurrentToken
	bridge.lock.Unlock()

	request.Header.Set("Authorization", "Bearer "+token)

	// Every Salesforce-bound request goes through this function, so the project is stamped
	// here rather than at each call site. When unset the header is omitted entirely, so the
	// request is indistinguishable from one sent by a bridge predating multi-project
	// support -- which is what makes either upgrade order safe.
	if bridge.projectKey != "" {
		request.Header.Set(PROJECT_HEADER, bridge.projectKey)
	}

	response, err := bridge.client.Do(request)
	if err != nil {
		return nil, err, false
	}

	if response.StatusCode == 401 || response.StatusCode == 403 {
		err, permanent := bridge.authorizeSalesforce()
		if err != nil {
			return nil, err, permanent
		}
	}

	return response, nil, false
}

func (bridge *Bridge) eventLoop() error {
	pollURI := bridge.salesforceURL + "event"
	pushURI := bridge.launchDarklyEventsURI + "/bulk"

	for {
		pollRequest, err := http.NewRequest("GET", pollURI, nil)
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

			pushRequest, err := http.NewRequest("POST", pushURI, bytes.NewBuffer(pollBytes))
			if err != nil {
				return errors.New("failed constructing event push request")
			}

			pushRequest.Header.Set("Content-Type", "application/json")
			pushRequest.Header.Set("X-LaunchDarkly-Event-Schema", "3")
			pushRequest.Header.Set("Authorization", bridge.launchDarklyKey)
			pushRequest.Header.Set("User-Agent", USER_AGENT)
			// Sent on every LaunchDarkly-bound request (matches the reference Go SDK,
			// where DefaultHeaders carries the instance id across poll/stream/events).
			pushRequest.Header.Set(INSTANCE_ID_HEADER, bridge.instanceID)

			log.Print("pushing events to: " + pushURI)

			pushResponse, err := bridge.client.Do(pushRequest)
			if err != nil {
				log.Print("failed pushing events to LaunchDarkly")
				goto End
			}
			// Only the status matters here, so the body is discarded rather than read.
			drainAndClose(pushResponse)

			if pushResponse.StatusCode == 401 || pushResponse.StatusCode == 403 {
				return errors.New("Pushing events to LaunchDarkly unauthorized")
			}

			if pushResponse.StatusCode != 200 && pushResponse.StatusCode != 202 {
				log.Print("event push expected 200/202 got: ", pushResponse.StatusCode)
				goto End
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
			pushRequest, err := http.NewRequest("POST", pushURI, bytes.NewBuffer(pollBytes))
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
