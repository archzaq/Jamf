#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 02-16-26   ###
###  Updated: 02-16-26   ###
###  Version: 1.0        ###
############################

readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly computerSerial=$(system_profiler SPHardwareDataType | awk '/Serial Number/ {print $NF}')

jamfURL="https://${4}"
clientID="$5"
clientSecret="$6"
accessToken=$(curl --silent --location \
	--request POST "${jamfURL}/api/oauth/token" \
	--header "Content-Type: application/x-www-form-urlencoded" \
	--data-urlencode "client_id=${clientID}" \
	--data-urlencode "grant_type=client_credentials" \
	--data-urlencode "client_secret=${clientSecret}" | plutil -extract "access_token" raw -o - -)

computerID=$(curl -s -H "Accept: application/xml" \
    -H "Authorization: Bearer $accessToken" \
    -X GET "${jamfURL}/JSSResource/computermanagement/serialnumber/${computerSerial}" | xmllint --xpath '/computer_management/general/id/text()' -)

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


