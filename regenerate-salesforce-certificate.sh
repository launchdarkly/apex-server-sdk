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

# Function to copy to clipboard using available utility
copy_to_clipboard() {
    if command -v pbcopy >/dev/null 2>&1; then
        # macOS
        cat "$1" | pbcopy
        echo "Private key copied to clipboard using pbcopy"
    elif command -v xclip >/dev/null 2>&1; then
        # Linux with xclip
        cat "$1" | xclip -selection clipboard
        echo "Private key copied to clipboard using xclip"
    elif command -v xsel >/dev/null 2>&1; then
        # Linux with xsel
        cat "$1" | xsel --clipboard --input
        echo "Private key copied to clipboard using xsel"
    else
        echo "No clipboard utility found (pbcopy, xclip, or xsel)"
        echo "Please manually copy the private key below:"
        echo "----------------------------------------"
        cat "$1"
        echo "----------------------------------------"
        return 1
    fi
}

read -p "(step 4/4) Put private key in clipboard? (y/n)" choice
case "$choice" in
y | Y) copy_to_clipboard server.key ;;
n | N) cat server.key ;;
*) echo "invalid choice" ;;
esac

rm server.key

echo "Manual step: upload server.crt to Salesforce"
read -p "Path: $WORK_DIR/server.crt (enter to proceed)"
read -p "Manual step: Update AWS SSM /production/common/releasing/apex/server.key with private key (enter to proceed)"

function cleanup {
    rm -r "$WORK_DIR"
}

echo "Cleaning up $WORK_DIR"

trap cleanup EXIT
