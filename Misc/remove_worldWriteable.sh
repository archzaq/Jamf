#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 03-25-26   ###
###  Updated: 08-27-26   ###
###  Version: 0.2        ###
############################

readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly currentUserHomePath="${HOME:-/Users/${currentUser}}"
readonly logFile='/var/log/remove_worldWriteable.log'

# Append current status to log file
function log_Message() {
	local message="$1"
	local type="${2:-Log}"
	local timestamp="$(date "+%F %T")"
	if [[ -w "$logFile" ]];
	then
		printf "%s: %s %s\n" "$type" "$timestamp" "$message" | tee -a "$logFile"
	else
		printf "%s: %s %s\n" "$type" "$timestamp" "$message"
	fi
}

function main() {
	if [[ -w "$logFile" ]];
	then
		printf "Log: $(date "+%F %T") Beginning Remove World Writable script\n" | tee "$logFile"
	else
		printf "Log: $(date "+%F %T") Beginning Remove World Writable script\n"
	fi

    # Find "World Writable" files and log them
	find "${currentUserHomePath}" -type f -perm -0002 -print0 | xargs -0 -I{} echo "World-writable: {}" >> "${logFile}"

    # Remove "World Writable" permission from file
	find "${currentUserHomePath}" -type f -perm -0002 -exec chmod o-w {} +

    exit 0
}

main

