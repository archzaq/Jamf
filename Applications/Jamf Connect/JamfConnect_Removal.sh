#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 7-25-23   ###
### Updated: 3-11-25   ###
### Version: 1.1       ###
##########################

readonly logPath='/var/log/JamfConnect_Removal.log'
readonly jamfConnectFilesArray=(
    "/usr/local/bin/authchanger"
    "/usr/local/lib/pam/pam_saml.so.2"
    "/Library/LaunchAgents/com.jamf.connect.plist"
    "/Library/Managed Preferences/com.jamf.connect.plist"
    "/Library/Managed Preferences/com.jamf.connect.login.plist"
    "/Library/Application Support/JAMF/Receipts/SLULogos_JamfConnect_5-30-23.pkg"
    "/Library/Application Support/JAMF/Receipts/SLULogos_JamfConnect_5-30-23-Signed.pkg"
    "/Library/Application Support/JAMF/Receipts/JamfConnectLaunchAgent.pkg" 
    "/Library/Application Support/JAMF/Receipts/JamfConnectLaunchAgent2.pkg"
    "/Library/Security/SecurityAgentPlugins/JamfConnectLogin.bundle"
    "/Applications/Jamf Connect.app"
)

# Append current status to log file
function log_Message() {
    echo "Log: $(date "+%F %T") $1" | tee -a "$logPath"
}

function main(){
    echo "Log: $(date "+%F %T") Beginning Jamf Connect Removal script." | tee "$logPath"

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
