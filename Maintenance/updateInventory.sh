#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 07-12-23  ###
### Updated: 09-06-25  ###
### Version: 3.4       ###
##########################

readonly jamfConnectPLIST='/Library/Managed Preferences/com.jamf.connect.plist'
readonly jamfConnectApp='/Applications/Jamf Connect.app'
readonly logPath='/var/log/updateInventory.log'
readonly maxAttempts=10

# Append current status to log file
function log_Message() {
    local message="$1"
    local logType="${2:-Log}"
    local timestamp="$(date "+%F %T")"
    printf "%s: %s %s\n" "$logType" "$timestamp" "$message" | tee -a "$logFile"
}

# Attempt to handle a jamf policy already being run
function check_PolicyStatus() {
    local checkResult="$1"
    local event="$2"
    local attempt=0
    while [[ $attempt -lt $maxAttempts ]];
    do
        if [[ $checkResult == *"already being run"* ]];
        then
            log_Message "Policy already being run, retrying in 30 seconds (Attempt $((attempt+1)))"
            sleep 30
            ((attempt++))
            if [[ ! -z "$event" ]];
            then
                checkResult=$(/usr/local/bin/jamf policy -event "$event")
            else
                checkResult=$(/usr/local/bin/jamf policy)
            fi
        else
            return 0
        fi
    done

    return 1
}

# Return false if the current device name doesnt fit naming scheme
function check_Name() {
    local name="$1"
    if [[ "$name" == *"Mac"* ]] || [[ "$name" == "SLU-"* ]];
    then
        return 1
    elif [[ "$name" == *-*-* ]];
    then
        return 0
    elif [[ "$name" == *"-"* ]];
    then
        return 0
    else
        return 1
    fi
}

function main() {
    /usr/bin/caffeinate -d &
    CAFFEINATE_PID=$!
    trap "kill $CAFFEINATE_PID" EXIT INT TERM HUP
    printf "Log: $(date "+%F %T") Beginning Update Inventory script\n" | tee "$logPath"

    log_Message "Checking for enrollment policies"
    enrollmentCheckResult=$(/usr/local/bin/jamf policy -event enrollmentComplete)
    if ! check_PolicyStatus "$enrollmentCheckResult" "enrollmentComplete";
    then
        log_Message "Checked $maxAttempts times, continuing"
    else
        log_Message "Enrollment policy check complete"
    fi

    sleep 1

    log_Message "Checking for policies"
    policyCheckResult=$(/usr/local/bin/jamf policy)
    if ! check_PolicyStatus "$policyCheckResult";
    then
        log_Message "Checked $maxAttempts times, continuing"
    else
        log_Message "Policy check complete"
    fi

    sleep 1

    log_Message "Updating inventory with Jamf Recon"
    /usr/local/bin/jamf recon 1>/dev/null
    log_Message "Inventory update finished"

    if [[ $(/usr/bin/uname -p) = 'arm' ]];
    then
        log_Message "Checking for Rosetta runtime"
        if [[ ! -f '/Library/Apple/usr/libexec/oah/libRosettaRuntime' ]];
        then
            log_Message "Rosetta runtime not present, installing Rosetta"
            /usr/sbin/softwareupdate --install-rosetta --agree-to-license
            sleep 1
            log_Message "Checking for other missing enrollment policies"
            /usr/local/bin/jamf policy -event enrollmentComplete
            if [ ! -f '/Library/Apple/usr/libexec/oah/libRosettaRuntime' ];
            then
                log_Message "Rosetta runtime still not found, trying install again then continuing regardless"
                /usr/sbin/softwareupdate --install-rosetta --agree-to-license
            else
                log_Message "Rosetta runtime found"
            fi
        else
            log_Message "Rosetta runtime present"
        fi
    fi

    sleep 1

    currentName=$(/usr/sbin/scutil --get LocalHostName)
    log_Message "Checking for correct naming"
    if ! check_Name "$currentName";
    then
        log_Message "Device name, \"$currentName\", does not fit naming scheme"
        /usr/local/bin/jamf policy -event rename
    else
        log_Message "Device name, \"$currentName\", fits naming scheme"
    fi

    sleep 1

    log_Message "Checking for Jamf Connect"
    if [[ ! -d "$jamfConnectApp" ]] || [[ ! -f "$jamfConnectPLIST" ]];
    then
        log_Message "Missing Jamf Connect, attempting install"
        if /usr/local/bin/jamf policy -event MissingJamfConnect;
        then
            log_Message "Jamf Connect policy finished"
        else
            log_Message "Unable to complete Jamf Connect policy" "ERROR"
            /usr/bin/osascript -e 'display alert "An error has occurred!" message "You must install Jamf Connect to authenticate properly at login" as critical'
        fi
    else
        log_Message "Jamf Connect already installed"
    fi

    log_Message "Exiting!"
    exit 0
}

main

