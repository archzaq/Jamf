#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 02-16-26   ###
###  Updated: 02-17-26   ###
###  Version: 1.1        ###
############################

# Information Variables
jamfURL="$4"
clientID="$5"
clientSecret="$6"
readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly computerSerial=$(system_profiler SPHardwareDataType | awk '/Serial Number/ {print $NF}')

# Ensure information variables are populated
if [[ -z "$jamfURL" ]] || [[ -z "$clientID" ]] || [[ -z "$clientSecret" ]];
then
    printf "Missing critical arguments\n"
    exit 1
fi

# Authenticate to obtain bearer token
accessToken=$(curl --silent --location \
	--request POST "${jamfURL}/api/oauth/token" \
	--header "Content-Type: application/x-www-form-urlencoded" \
	--data-urlencode "client_id=${clientID}" \
	--data-urlencode "grant_type=client_credentials" \
	--data-urlencode "client_secret=${clientSecret}" | plutil -extract "access_token" raw -o - -)

# Ensure access token is populated
if [[ -z "$accessToken" ]];
then
    printf "Missing access token\n"
    exit 1
fi

# Grab current device ID using the serial
computerID=$(curl -s -H "Accept: application/xml" \
    -H "Authorization: Bearer $accessToken" \
    -X GET "${jamfURL}/JSSResource/computermanagement/serialnumber/${computerSerial}" | xmllint --xpath '/computer_management/general/id/text()' -)

# Ensure computer ID is populated
if [[ -z "$computerID" ]];
then
    printf "Missing computer ID\n"
    exit 1
fi

# Get existing update status
existingStatus=$(curl -s -H "Accept: application/json" \
    -H "Authorization: Bearer $accessToken" \
    -X GET "${jamfURL}/api/v1/managed-software-updates/update-statuses/computers/${computerID}")

totalCount=$(echo "$existingStatus" | plutil -extract "totalCount" raw -o - -)

if [[ "$totalCount" -gt 0 ]];
then
    planStatus=$(echo "$existingStatus" | plutil -extract "results.0.status" raw -o - -)
    
    if [[ "$planStatus" == "IDLE" || "$planStatus" == "FAILED" ]];
    then
        # Flush pending commands to clear stale plans
        curl -s -H "Authorization: Bearer $accessToken" \
            -X DELETE "${jamfURL}/JSSResource/commandflush/computers/id/${computerID}/status/Pending"
        printf "Cleared stale plans\n"
    else
        printf "Update already actively in progress\n"
        exit 0
    fi
fi

# Push minor macOS update
curl -s -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $accessToken" \
    -X POST "${jamfURL}/api/v1/managed-software-updates/plans" \
    -d '{
        "devices": [
            {
                "deviceId": "'"$computerID"'",
                "objectType": "COMPUTER"
            }
        ],
        "config": {
            "updateAction": "DOWNLOAD_INSTALL_RESTART",
            "versionType": "LATEST_MINOR"
        }
    }'

