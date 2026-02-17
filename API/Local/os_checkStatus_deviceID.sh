#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 02-16-26   ###
###  Updated: 02-16-26   ###
###  Version: 1.0        ###
############################

readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
computerID="$1"

if [[ -z "$computerID" ]];
then
    printf "Missing Computer ID as argument\n"
    exit 1
fi

# Authenticate
jamfURL="https://$(security find-generic-password -s "jamf-api-url" -a "$currentUser" -w)"
clientID=$(security find-generic-password -s "jamf-api-id" -a "$currentUser" -w)
clientSecret=$(security find-generic-password -s "jamf-api-sec" -a "$currentUser" -w)
accessToken=$(curl --silent --location \
	--request POST "${jamfURL}/api/oauth/token" \
	--header "Content-Type: application/x-www-form-urlencoded" \
	--data-urlencode "client_id=${clientID}" \
	--data-urlencode "grant_type=client_credentials" \
	--data-urlencode "client_secret=${clientSecret}" | plutil -extract "access_token" raw -o - -)

curl -s -H "Accept: application/json" \
    -H "Authorization: Bearer $accessToken" \
    -X GET "${jamfURL}/api/v1/managed-software-updates/update-statuses/computers/${computerID}"
