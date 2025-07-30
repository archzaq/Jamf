#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 07-12-23  ###
### Updated: 07-30-25  ###
### Version: 3.1       ###
##########################

currentName=$(/usr/sbin/scutil --get LocalHostName)
readonly jamfConnectPLIST='/Library/Managed Preferences/com.jamf.connect.plist'
readonly jamfConnectApp='/Applications/Jamf Connect.app'
readonly logPath='/var/log/updateInventory.log'
readonly maxAttempts=10

# Append current status to log file
function log_Message() {
    local timestamp="$(date "+%F %T")"
    printf "Log: %s %s\n" "$timestamp" "$1" | tee -a "$logPath"
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
    if [[ "$currentName" == *"Mac"* ]] || [[ "$currentName" == "SLU-"* ]];
    then
        return 1
    elif [[ "$currentName" == *-*-* ]];
    then
        return 0
    elif [[ "$currentName" == *"-"* ]];
    then
        return 0
    else
        return 1
    fi
}

function main() {
    /usr/bin/caffeinate -d &
    CAFFEINATE_PID=$!
    trap "kill $CAFFEINATE_PID" EXIT
    printf "Log: $(date "+%F %T") Beginning Update Inventory script.\n" | tee "$logPath"

    log_Message "Checking for lingering enrollment policies"
    enrollmentCheckResult=$(/usr/local/bin/jamf policy -event enrollmentComplete)
    if ! check_PolicyStatus "$enrollmentCheckResult" "enrollmentComplete";
    then
        log_Message "Checked $maxAttempts times, giving up"
    else
        log_Message "Enrollment policy check complete"
    fi

    sleep 1

    log_Message "Checking for remaining standard policies"
    policyCheckResult=$(/usr/local/bin/jamf policy)
    if ! check_PolicyStatus "$policyCheckResult";
    then
        log_Message "Checked $maxAttempts times, giving up"
    else
        log_Message "Standard policy check complete"
    fi

    sleep 1

    log_Message "Updating inventory"
    /usr/local/bin/jamf recon
    log_Message "Inventory update complete"

    if [[ $(/usr/bin/uname -p) = 'arm' ]];
    then
        log_Message "Checking for Rosetta runtime"
        if [[ ! -f /Library/Apple/usr/libexec/oah/libRosettaRuntime ]];
        then
            log_Message "Rosetta runtime not present, installing Rosetta"
            /usr/sbin/softwareupdate --install-rosetta --agree-to-license
            sleep 1
            log_Message "Checking for other missing enrollment policies"
            /usr/local/bin/jamf policy -event enrollmentComplete
            if [ ! -f /Library/Apple/usr/libexec/oah/libRosettaRuntime ];
            then
                log_Message "Rosetta runtime still not present, trying install again"
                /usr/sbin/softwareupdate --install-rosetta --agree-to-license
            fi
        else
            log_Message "Rosetta runtime present"
        fi
        log_Message "Rosetta runtime check complete"
    fi

    sleep 1

    currentName=$(/usr/sbin/scutil --get LocalHostName)
    log_Message "Checking for correct naming"
    if ! check_Name;
    then
        log_Message "Device name, \"$currentName\", does not fit naming scheme"
        /usr/local/bin/jamf policy -event rename
    else
        log_Message "Device name, \"$currentName\", fits naming scheme"
    fi
    log_Message "Name check complete"

    sleep 1

    log_Message "Checking for Jamf Connect"
    if [[ ! -d "$jamfConnectApp" ]] || [[ ! -f "$jamfConnectPLIST" ]];
    then
        log_Message "Missing Jamf Connect, installing"
        /usr/local/bin/jamf policy -event MissingJamfConnect
    else
        log_Message "Jamf Connect already installed"
    fi

    log_Message "Exiting!"
    exit 0
}

main

