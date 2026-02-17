
#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 02-16-26   ###
###  Updated: 02-17-26   ###
###  Version: 0.2        ###
############################

readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
jamfURL="$(security find-generic-password -s "jamf-api-url" -a "$currentUser" -w)"
clientID="$(security find-generic-password -s "jamf-api-id" -a "$currentUser" -w)"
clientSecret="$(security find-generic-password -s "jamf-api-sec" -a "$currentUser" -w)"

if [[ -z "$jamfURL" ]] || [[ -z "$clientID" ]] || [[ -z "$clientSecret" ]];
then
    printf "Missing critical arguments\n"
    exit 1
fi

accessToken=$(curl --silent --location \
	--request POST "${jamfURL}/api/oauth/token" \
	--header "Content-Type: application/x-www-form-urlencoded" \
	--data-urlencode "client_id=${clientID}" \
	--data-urlencode "grant_type=client_credentials" \
	--data-urlencode "client_secret=${clientSecret}" | plutil -extract "access_token" raw -o - -)

if [[ -z "$accessToken" ]];
then
    printf "Missing access token\n"
    exit 1
fi

response=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer $accessToken" \
    -X GET "${jamfURL}/api/v2/jamf-pro-information")

if [[ "$response" == "200" ]] || [[ "$response" -eq 200 ]];
then
    printf "Valid Bearer Token\n"
else
    printf "Failed: %s\n" "$response"
    exit 1
fi

exit 0


