#!/bin/bash

# This script can be used to assist in regenerating the credentials necessary to implement the
# "JWT Bearer authorization flow" for connected Salesforce apps.
#
# The purpose is to allow this SDK to be automatically tested in CI against LaunchDarkly's scratch org.

# See also:
# https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_auth_connected_app.htm
# (information on how to store the generated certificate in Salesforce)
#
# The KEY_SIZE and DAYS_VALID env variables must be set.
# KEY_SIZE minimum value is recommended as 2048.
# DAYS_VALID maximum value is recommended as 365.

WORK_DIR=$(mktemp -d)
cd "$WORK_DIR" || exit

if [[ -z "${KEY_SIZE}" ]]; then
  echo "Must set KEY_SIZE environment variable"
  exit
fi

if [[ -z "${DAYS_VALID}" ]]; then
  echo "Must set DAYS_VALID environment variable"
  exit
fi

echo -e "The working directory is $WORK_DIR\n\n"

echo "(step 1/4) Generating private key"
openssl genrsa -out server.key "$KEY_SIZE"

echo "(step 2/4) Generating certificate signing request"
openssl req -new -key server.key -out server.csr

echo "(step 3/4) Generating certificate"
openssl x509 -req -sha256 -days "$DAYS_VALID" -in server.csr -signkey server.key -out server.crt
rm server.csr

read -p "(step 4/4) Base64 encoding the private key. Put in clipboard? (y/n)" choice
case "$choice" in
  y|Y ) base64 -i server.key | pbcopy;;
  n|N ) base64 -i server.key;;
  * ) echo "invalid choice";;
esac

rm server.key

echo "Manual step: upload server.crt to Salesforce"
read -p "Path: $WORK_DIR/server.crt (enter to proceed)"
read -p "Manual step: set the SFDX_CONSUMER_KEY context var to the connected app's consumer key (enter to proceed)"
read -p "Manual step: Set the SFDX_JWT_KEY context var to the base64 encoded private key (enter to proceed)"

function cleanup {
  rm -r "$WORK_DIR"
}

echo "Cleaning up $WORK_DIR"

trap cleanup EXIT
