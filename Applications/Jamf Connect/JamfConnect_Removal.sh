#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 07-25-23  ###
### Updated: 12-11-25  ###
### Version: 1.2       ###
##########################

readonly logFile='/var/log/JamfConnect_Removal.log'
readonly jamfConnectFilesArray=(
    "/usr/local/lib/pam/pam_saml.so.2"
    "/Library/LaunchAgents/com.jamf.connect.plist"
    "/Library/Managed Preferences/com.jamf.connect.plist"
    "/Library/Managed Preferences/com.jamf.connect.login.plist"
    "/Library/Managed Preferences/com.jamf.connect.shares.plist"
    "/Library/Application Support/JAMF/Receipts/SLULogos_JamfConnect_5-30-23.pkg"
    "/Library/Application Support/JAMF/Receipts/SLULogos_JamfConnect_5-30-23-Signed.pkg"
    "/Library/Application Support/JAMF/Receipts/JamfConnectLaunchAgent.pkg" 
    "/Library/Application Support/JAMF/Receipts/JamfConnectLaunchAgent2.pkg"
    "/Library/Security/SecurityAgentPlugins/JamfConnectLogin.bundle"
    "/Library/Application Support/JamfConnect"
    "/Applications/Jamf Connect.app"
)

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

function main(){
	if [[ -w "$logFile" ]];
	then
		printf "Log: $(date "+%F %T") Beginning Jamf Connect Removal script\n" | tee "$logFile"
	else
		printf "Log: $(date "+%F %T") Beginning Jamf Connect Removal script\n"
	fi

    # Check if authchanger command exists
    if ! command -v /usr/local/bin/authchanger >/dev/null 2>&1;
    then
        log_Message "authchanger command not found."
    else
        log_Message "authchanger reset."
        /usr/local/bin/authchanger -reset
    fi

    sleep 1

    # Remove Jamf Connect files
    for jamfConnectFile in "${jamfConnectFilesArray[@]}";
    do
        if [ -f "$jamfConnectFile" ];
        then
            log_Message "Removing $jamfConnectFile"
            rm "$jamfConnectFile"
        elif [ -d "$jamfConnectFile" ];
        then
            log_Message "Removing $jamfConnectFile"
            rm -r "$jamfConnectFile"
        else
            log_Message "Skipping $jamfConnectFile"
        fi
    done

    # Kill Jamf Connect
    if pgrep "Jamf Connect" >/dev/null;
    then
        log_Message "Killing Jamf Connect."
        pkill "Jamf Connect"
    else
        log_Message "Jamf Connect not running"
    fi

    exit 0
}

main
