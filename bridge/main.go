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
	OAUTH_ID := getEnvRequired("OAUTH_ID")
	OAUTH_SECRET := getEnvRequired("OAUTH_SECRET")
	OAUTH_REFRESH_TOKEN := getEnvRequired("OAUTH_REFRESH_TOKEN")

	client := &http.Client{}

	query := url.Values{}
	query.Add("grant_type", "refresh_token")
	query.Add("client_id", OAUTH_ID)
	query.Add("client_secret", OAUTH_SECRET)
	query.Add("refresh_token", OAUTH_REFRESH_TOKEN)

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

	// authString := string(authBytes)
	// log.Print(authString)

	var parsed AuthBody;
	json.Unmarshal(authBytes, &parsed)

	if parsed.AccessToken == "" {
		log.Panic("expected access token in body")
	}

	return parsed.AccessToken
}

func main() {
	LD_SDK_KEY := getEnvRequired("LD_SDK_KEY")
	SALESFORCE_URL := getEnvRequired("SALESFORCE_URL")

	tokenSalesForce := getAuthorization()

	client := &http.Client{}

	var etag = ""

	for {
		pollURI := LD_BASE_URI + "/sdk/latest-all"

		pollRequest, err := http.NewRequest("GET", pollURI, nil)

		if err != nil {
			log.Panic("failed constructing poll request ", err)
		}

		pollRequest.Header.Set("Authorization", LD_SDK_KEY)

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
				log.Print("poll received 304 skipping update")

				goto End
			}

			if pollResponse.StatusCode != 200 {
				log.Print("poll expected 200")

				goto End
			}

			etag = ""

			pollBytes, err := ioutil.ReadAll(pollResponse.Body)

			if err != nil {
				log.Panic("failed to read poll response body")
			}

			// pollString := string(pollBytes)
			// log.Print(pollString)

			pushURI := SALESFORCE_URL + "store"

			pushRequest, err := http.NewRequest("POST", pushURI, bytes.NewBuffer(pollBytes))

			if err != nil {
				log.Panic("failed constructing push request ", err)
			}

			pushRequest.Header.Set("Content-Type", "application/json")
			pushRequest.Header.Set("Authorization", "Bearer " + tokenSalesForce)

			log.Print("pushing flags to: " + pushURI)

			pushResponse, err := client.Do(pushRequest)

			if err != nil {
				log.Panic("failed getting test from salesforce")
			}

			if pushResponse.StatusCode == 401 || pushResponse.StatusCode == 403 {
				log.Panic("pushing flags unauthorized")
			}

			if pushResponse.StatusCode != 200 {
				log.Print("push expected 200")

				goto End
			}

			etag = pollResponse.Header.Get("ETag")
		}

	End:
		log.Print("waiting for: ", POLL_INTERVAL)

		time.Sleep(POLL_INTERVAL)
	}
}
