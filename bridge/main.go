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
	"io/ioutil"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	LD_BASE_URI   = "https://sdk.launchdarkly.com"
	LD_EVENTS_URI = "https://events.launchdarkly.com"
	OAUTH_URI     = "https://login.salesforce.com/services/oauth2/token"
	POLL_INTERVAL = 30 * time.Second
	SDK_VERSION   = "1.1.1"
	USER_AGENT    = "ApexServerClient/" + SDK_VERSION
	HTTP_TIMEOUT  = 30 * time.Second
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
	lock                  sync.Mutex
	context               context.Context
	cancel                context.CancelFunc
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

	bridge.client = http.Client{
		Timeout: httpTimeoutDuration,
	}

	context, cancel := context.WithCancel(context.Background())
	bridge.context = context
	bridge.cancel = cancel

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

func (bridge *Bridge) requestWithOauth(request *http.Request) (*http.Response, error, bool) {
	bridge.lock.Lock()
	token := bridge.oauthCurrentToken
	bridge.lock.Unlock()

	request.Header.Set("Authorization", "Bearer "+token)

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
				log.Print("poll events expected 200 but got ", pollResponse.StatusCode)
				goto End
			}

			pollBytes, err := ioutil.ReadAll(pollResponse.Body)
			if err != nil {
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

			log.Print("pushing events to: " + pushURI)

			pushResponse, err := bridge.client.Do(pushRequest)

			if err != nil {
				log.Print("failed pushing events to LaunchDarkly")
				goto End
			}

			if pushResponse.StatusCode == 401 || pushResponse.StatusCode == 403 {
				return errors.New("Pushing events to LaunchDarkly unauthorized")
			}

			if pushResponse.StatusCode != 200 && pushResponse.StatusCode != 202 {
				log.Print("event push expected 200/202 got: ", pushResponse.StatusCode)
				goto End
			}
		}

	End:
		log.Print("event polling waiting for: ", POLL_INTERVAL)

		select {
		case <-bridge.context.Done():
			return nil
		case <-time.After(POLL_INTERVAL):
		}
	}
}

func (bridge *Bridge) featureLoop() error {
	var etag = ""

	pollURI := bridge.launchDarklyBaseURI + "/sdk/latest-all"

	for {
		pollRequest, err := http.NewRequest("GET", pollURI, nil)
		if err != nil {
			return err
		}

		pollRequest.Header.Set("Authorization", bridge.launchDarklyKey)
		pollRequest.Header.Set("User-Agent", USER_AGENT)

		if etag != "" {
			pollRequest.Header.Set("If-None-Match", etag)
		}

		log.Print("requesting flags from: " + pollURI)

		pollResponse, err := bridge.client.Do(pollRequest)

		if err != nil {
			log.Print("poll flags failed: ", err)

			goto End
		} else {
			if pollResponse.StatusCode == 401 || pollResponse.StatusCode == 403 {
				return errors.New("requesting flags unauthorized")
			}

			if pollResponse.StatusCode == 304 {
				log.Print("poll flags received 304 skipping update")
				goto End
			}

			if pollResponse.StatusCode != 200 {
				log.Print("poll flags expected 200, got ", pollResponse.StatusCode)
				goto End
			}

			etag = ""

			pollBytes, err := ioutil.ReadAll(pollResponse.Body)
			if err != nil {
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

			if pushResponse.StatusCode != 200 {
				log.Print("push flags expected 200 got ", pushRequest)
				goto End
			}

			etag = pollResponse.Header.Get("ETag")
		}

	End:
		log.Print("feature polling waiting for: ", POLL_INTERVAL)

		select {
		case <-bridge.context.Done():
			return nil
		case <-time.After(POLL_INTERVAL):
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
		log.Print("Error creating bridge: ", err)
		return
	}

	err = bridge.run()
	if err != nil {
		log.Print("Error running bridge: ", err)
		return
	}
}
