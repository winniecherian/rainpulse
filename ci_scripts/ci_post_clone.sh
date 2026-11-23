#!/bin/sh
# Xcode Cloud runs this after cloning. It turns the workflow's environment
# variables (mark them "Secret") into Config/Secrets.xcconfig.
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH"
cat > Config/Secrets.xcconfig <<SECRETS
OWM_API_KEY = ${OWM_API_KEY}
TOMORROW_API_KEY = ${TOMORROW_API_KEY}
OPEN_METEO_API_KEY = ${OPEN_METEO_API_KEY}
SECRETS
echo "Secrets.xcconfig written"
