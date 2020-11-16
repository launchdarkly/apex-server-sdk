package main

import (
	"bytes"
	"encoding/json"
	"io/ioutil"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

const (
	LD_BASE_URI   = "https://app.launchdarkly.com"
	LD_EVENTS_URI = "https://events.launchdarkly.com"
	OAUTH_URI     = "https://login.salesforce.com/services/oauth2/token"
	POLL_INTERVAL = 30 * time.Second
)

type AuthBody struct {
	AccessToken string `json:"access_token"`
}

func getEnvRequired(env string) string {
	if tmp := os.Getenv(env); tmp != "" {
		return tmp;
	} else {
		log.Panic(env+" required")
		// impossible but compiler warns
		return "";
	}
}

func getAuthorization() string {
	oauthId := getEnvRequired("OAUTH_ID")
	oauthSecret := getEnvRequired("OAUTH_SECRET")
	oauthUsername := getEnvRequired("OAUTH_USERNAME")
	oauthPassword := getEnvRequired("OAUTH_PASSWORD")

	client := &http.Client{}

	query := url.Values{}
	query.Add("grant_type", "password")
	query.Add("client_id", oauthId)
	query.Add("client_secret", oauthSecret)
	query.Add("username", oauthUsername)
	query.Add("password", oauthPassword)

	authRequest, err := http.NewRequest("POST", OAUTH_URI, strings.NewReader(query.Encode()))

	if err != nil {
		log.Panic("failed constructing auth request ", err)
	}

	authRequest.Header.Add("Content-Type", "application/x-www-form-urlencoded")

	authResponse, err := client.Do(authRequest)

	if err != nil {
		log.Panic("failed getting oauth token")
	}

	if authResponse.StatusCode != 200 {
		log.Panic("failed getting oauth token expected 200 got ", authResponse.StatusCode)
	}

	authBytes, err := ioutil.ReadAll(authResponse.Body)

	if err != nil {
		log.Panic("failed to read auth response body")
	}

	var parsed AuthBody;
	json.Unmarshal(authBytes, &parsed)

	if parsed.AccessToken == "" {
		log.Panic("expected access token in body")
	}

	return parsed.AccessToken
}

// Pull events from Salesforce and send them to LaunchDarkly
func eventLoop(salesforceURL string, launchDarklyKey string, salesforceToken string) {
	client := &http.Client{}

	pollURI := salesforceURL + "event"
	pushURI := LD_EVENTS_URI + "/bulk"

	for {
		pollRequest, err := http.NewRequest("GET", pollURI, nil)

		pollRequest.Header.Set("Content-Type", "application/json")
		pollRequest.Header.Set("Authorization", "Bearer " + salesforceToken)

		log.Print("requesting events from: " + pollURI)

		pollResponse, err := client.Do(pollRequest)

		if err != nil {
			log.Print("poll events failed")

			goto End
		} else {
			if pollResponse.StatusCode != 200 {
				log.Print("poll events expected 200")

				goto End
			}
			
			pollBytes, err := ioutil.ReadAll(pollResponse.Body)

			if err != nil {
				log.Panic("failed to read poll events response body")
			}

			pushRequest, err := http.NewRequest("POST", pushURI, bytes.NewBuffer(pollBytes))

			if err != nil {
				log.Panic("failed constructing event push request ", err)
			}

			pushRequest.Header.Set("Content-Type", "application/json")
			pushRequest.Header.Set("X-LaunchDarkly-Event-Schema", "3")
			pushRequest.Header.Set("Authorization", launchDarklyKey)

			log.Print("pushing events to: " + pushURI)

			pushResponse, err := client.Do(pushRequest)

			if err != nil {
				log.Panic("failed pushing events to LaunchDarkly")
			}

			if pushResponse.StatusCode == 401 || pushResponse.StatusCode == 403 {
				log.Panic("pushing events unauthorized")
			}

			if pushResponse.StatusCode != 200 && pushResponse.StatusCode != 202 {
				log.Print("event push expected 200/202 got: ", pushResponse.StatusCode);

				goto End
			}
		}

	End:
		log.Print("event polling waiting for: ", POLL_INTERVAL)

		time.Sleep(POLL_INTERVAL)
	}
}

// Pull flags from LaunchDarkly and send them to Salesforce
func featureLoop(salesforceURL string, launchDarklyKey string, salesforceToken string) {
	client := &http.Client{}

	var etag = ""

	for {
		pollURI := LD_BASE_URI + "/sdk/latest-all"

		pollRequest, err := http.NewRequest("GET", pollURI, nil)

		if err != nil {
			log.Panic("failed constructing flag poll request ", err)
		}

		pollRequest.Header.Set("Authorization", launchDarklyKey)

		if etag != "" {
			pollRequest.Header.Set("If-None-Match", etag)
		}

		log.Print("requesting flags from: " + pollURI)

		pollResponse, err := client.Do(pollRequest)

		if err != nil {
			log.Print("poll flags failed")

			goto End
		} else {
			if pollResponse.StatusCode == 401 || pollResponse.StatusCode == 403 {
				log.Panic("requesting flags unauthorized")
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
				log.Panic("failed to read flag poll response body")
			}

			pushURI := salesforceURL + "store"

			pushRequest, err := http.NewRequest("POST", pushURI, bytes.NewBuffer(pollBytes))

			if err != nil {
				log.Panic("failed constructing flag push request ", err)
			}

			pushRequest.Header.Set("Content-Type", "application/json")
			pushRequest.Header.Set("Authorization", "Bearer " + salesforceToken)

			log.Print("pushing flags to: " + pushURI)

			pushResponse, err := client.Do(pushRequest)

			if err != nil {
				log.Panic("failed pushings flags to salesforce")
			}

			if pushResponse.StatusCode == 401 || pushResponse.StatusCode == 403 {
				log.Panic("pushing flags unauthorized")
			}

			if pushResponse.StatusCode != 200 {
				log.Print("push flags expected 200 got ", pushRequest)

				goto End
			}

			etag = pollResponse.Header.Get("ETag")
		}

	End:
		log.Print("feature polling waiting for: ", POLL_INTERVAL)

		time.Sleep(POLL_INTERVAL)
	}
}

func main() {
	launchDarklyKey := getEnvRequired("LD_SDK_KEY")
	salesforceURL := getEnvRequired("SALESFORCE_URL")

 	salesforceToken := getAuthorization()

	go eventLoop(salesforceURL, launchDarklyKey, salesforceToken)
	
	featureLoop(salesforceURL, launchDarklyKey, salesforceToken)
}
