#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 00-00-00  ###
### Updated: 12-24-25  ###
### Version: 1.0       ###
##########################

readonly logFile='/var/log/JamfConnect_Reinstall.log'

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
		printf "Log: $(date "+%F %T") Beginning Jamf Connect Reinstall script\n" | tee "$logFile"
	else
		printf "Log: $(date "+%F %T") Beginning Jamf Connect Reinstall script\n"
	fi

    /usr/bin/caffeinate -d &
    caffeinatePID=$!
    trap "kill $caffeinatePID" EXIT INT TERM HUP

    log_Message "Checking for current Jamf Connect installation"
    if [ -f "/Library/LaunchAgents/com.jamf.connect.plist" ] || [ -d "/Applications/Jamf Connect.app" ] || [ -d "/Library/Security/SecurityAgentPlugins/JamfConnectLogin.bundle" ];
    then
        log_Message "Removing current Jamf Connect installation"
        if /usr/local/bin/jamf policy -event RemoveJamfConnect;
        then
            log_Message "RemoveJamfConnect policy completed"
        else
            log_Message "Unable to complete RemoveJamfConnect policy" "WARN"
        fi
    else
        log_Message "No Jamf Connect installation found"
    fi

    sleep 1

    log_Message "Beginning the installation of Jamf Connect"
    if /usr/local/bin/jamf policy -event InstallJamfConnect;
    then
        log_Message "InstallJamfConnect policy completed"
    else
        log_Message "Unable to complete InstallJamfConnect policy" "WARN"
    fi

    exit 0
}

main

