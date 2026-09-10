#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 00-00-00   ###
###  Updated: 00-00-00   ###
###  Version: 0.1        ###
############################

readonly scriptName='remote_FixMDMEnrollment'
readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly logFile="/var/log/${scriptName}.log"

# Append current status to log file
function log_Message() {
	local message="$1"
	local type="${2:-Log}"
	local timestamp="$(date "+%F %T")"
	printf "%s: %s %s\n" "$type" "$timestamp" "$message" >> "$logFile"
}

function main() {
	printf "Log: $(date "+%F %T") Beginning ${scriptName} script\n" > "$logFile"

    userID=$(id -u "$currentUser")
    nohup launchctl asuser "$userID" sudo -u "$currentUser" /usr/bin/osascript -e 'display dialog "Process completed successfully!" buttons {"OK"}' >/dev/null 2>&1 </dev/null &
    disown
    exit 0
}

main
