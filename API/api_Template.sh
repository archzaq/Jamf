#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 02-16-26   ###
###  Updated: 02-16-26   ###
###  Version: 0.1        ###
############################

readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"

# Authenticate
baseURL=$(security find-generic-password -s "jamf-api-url" -a "$currentUser" -w)
clientID=$(security find-generic-password -s "jamf-api-id" -a "$currentUser" -w)
clientSecret=$(security find-generic-password -s "jamf-api-sec" -a "$currentUser" -w)
accessToken=$(curl --silent --location \
	--request POST "https://${baseURL}/api/oauth/token" \
	--header "Content-Type: application/x-www-form-urlencoded" \
	--data-urlencode "client_id=${clientID}" \
	--data-urlencode "grant_type=client_credentials" \
	--data-urlencode "client_secret=${clientSecret}" | plutil -extract "access_token" raw -o - -)

# Make GET call for Buildings to test authentication
response=$(curl -s -o /dev/null -w "%{response_code}" \
    -H "Accept: application/xml" \
    -H "Authorization: Bearer $accessToken" \
    -X GET "https://${baseURL}/JSSResource/buildings")

if [[ "$response" -eq 200 ]];
then
    printf "It worked!\n"
else
    printf "Failed with HTTP %s\n" "$response"
    exit 1
fi


