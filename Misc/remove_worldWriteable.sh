#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 03-25-26   ###
###  Updated: 03-25-26   ###
###  Version: 0.1        ###
############################

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
		printf "Log: $(date "+%F %T") Beginning Remove World Writeable script\n" | tee "$logFile"
	else
		printf "Log: $(date "+%F %T") Beginning Remove World Writeable script\n"
	fi

    # PaperCut Client
    if [[ -d "/Applications/PCClient.app" ]];
    then
        chmod -R o-w "/Applications/PCClient.app"
    fi

    # PaperCut Print Deploy Client
    if [[ -d "/Applications/PaperCut Print Deploy Client" ]];
    then
        chmod -R o-w "/Applications/PaperCut Print Deploy Client"
    fi

    # PaperCut LaunchAgent
    if [[ -f "/Library/LaunchAgents/com.papercut.client.plist" ]];
    then
        chmod o-w "/Library/LaunchAgents/com.papercut.client.plist"
    fi

    # Adobe system level
    chmod -R o-w "/Library/Application Support/Adobe/"
    chmod o-w "/Library/Logs/adobegc.log"
    chmod o-w "/Library/Logs/CreativeCloud/ACC/ACC.log"
    chmod -R o-w "/Library/Logs/Adobe/"
    chmod o-w "/Library/Preferences/com.adobe.AdobeGenuineService.plist"

    # Adobe user level
    chmod -R o-w "/Users/Shared/Adobe*"
    chmod -R o-w "/Users/Shared/AdobeGC*"

    exit 0
}

main

