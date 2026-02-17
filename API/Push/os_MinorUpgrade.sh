#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 02-16-26   ###
###  Updated: 02-17-26   ###
###  Version: 1.3        ###
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
printf "Computer ID: $computerID\n"

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
printf "Existing Status: $existingStatus\n"

totalCount=$(echo "$existingStatus" | plutil -extract "totalCount" raw -o - -)
printf "Total Count: $totalCount\n"

if [[ "$totalCount" -gt 0 ]];
then
    planStatus=$(echo "$existingStatus" | plutil -extract "results.0.status" raw -o - -)
    planUUID=$(echo "$existingStatus" | plutil -extract "results.0.planUuid" raw -o - -)
    printf "Plan Status: $planStatus\n"
    printf "Plan UUID: $planUUID\n"

    # If we got a plan UUID, investigate its declarations and events before flushing
    if [[ -n "$planUUID" ]];
    then
        printf "\nPRE-FLUSH: Plan Declarations\n"
        planDeclarations=$(curl -s -H "Accept: application/json" \
            -H "Authorization: Bearer $accessToken" \
            -X GET "${jamfURL}/api/v1/managed-software-updates/plans/${planUUID}/declarations")
        printf "$planDeclarations\n"

        printf "\nPRE-FLUSH: Plan Events\n"
        planEvents=$(curl -s -H "Accept: application/json" \
            -H "Authorization: Bearer $accessToken" \
            -X GET "${jamfURL}/api/v1/managed-software-updates/plans/${planUUID}/events")
        printf "$planEvents\n"

        printf "\nPRE-FLUSH: Pending Commands\n"
        pendingCommands=$(curl -s -H "Accept: application/xml" \
            -H "Authorization: Bearer $accessToken" \
            -X GET "${jamfURL}/JSSResource/computermanagement/id/${computerID}" | xmllint --xpath '//pending_commands' - 2>/dev/null)
        printf "$pendingCommands\n"
    fi

    if [[ "$planStatus" == "IDLE" || "$planStatus" == "FAILED" ]];
    then
        # Flush pending commands to clear stale plans
        printf "\nFLUSHING PENDING COMMANDS\n"
        flushResult=$(curl -s -H "Authorization: Bearer $accessToken" \
            -X DELETE "${jamfURL}/JSSResource/commandflush/computers/id/${computerID}/status/Pending")
        printf "Flush Result: $flushResult\n"

        # Brief pause to allow Jamf to process the flush
        sleep 5

        # Re-check everything after flush
        if [[ -n "$planUUID" ]];
        then
            printf "\nPOST-FLUSH: Plan Status\n"
            postFlushStatus=$(curl -s -H "Accept: application/json" \
                -H "Authorization: Bearer $accessToken" \
                -X GET "${jamfURL}/api/v1/managed-software-updates/update-statuses/computers/${computerID}")
            printf "$postFlushStatus\n"

            printf "\nPOST-FLUSH: Plan Events\n"
            postFlushEvents=$(curl -s -H "Accept: application/json" \
                -H "Authorization: Bearer $accessToken" \
                -X GET "${jamfURL}/api/v1/managed-software-updates/plans/${planUUID}/events")
            printf "$postFlushEvents\n"

            printf "\nPOST-FLUSH: Pending Commands\n"
            postFlushPending=$(curl -s -H "Accept: application/xml" \
                -H "Authorization: Bearer $accessToken" \
                -X GET "${jamfURL}/JSSResource/computermanagement/id/${computerID}" | xmllint --xpath '//pending_commands' - 2>/dev/null)
            printf "$postFlushPending\n"
        fi

        printf "\nCleared stale plans\n"
    else
        printf "Update already actively in progress\n"
        exit 0
    fi
fi

# Dont update, exit
exit 0

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
