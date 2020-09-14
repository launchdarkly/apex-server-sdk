package main

import (
	"bytes"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"time"
)

const (
	LD_BASE_URI   = "https://app.launchdarkly.com"
	POLL_INTERVAL = 30 * time.Second
)

func main() {
	LD_SDK_KEY := os.Getenv("LD_SDK_KEY")

	if LD_SDK_KEY == "" {
		log.Panic("LD_SDK_KEY required")
	}

	SALESFORCE_KEY := os.Getenv("SALESFORCE_KEY")

	if SALESFORCE_KEY == "" {
		log.Panic("SALESFORCE_KEY required")
	}

	SALESFORCE_URL := os.Getenv("SALESFORCE_URL")

	if SALESFORCE_URL == "" {
		log.Panic("SALESFORCE_URL required")
	}

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
			pushRequest.Header.Set("Authorization", "Bearer " + SALESFORCE_KEY)

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
