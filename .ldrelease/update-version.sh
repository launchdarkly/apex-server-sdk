#!/bin/bash

set -e

TARGET_FILE=bridge/main.go
TEMP_FILE=${TARGET_FILE}.tmp

sed "s/^	SDK_VERSION .*/	SDK_VERSION   = \"${LD_RELEASE_VERSION}\"/" "${TARGET_FILE}" > "${TEMP_FILE}"
mv "${TEMP_FILE}" "${TARGET_FILE}"
