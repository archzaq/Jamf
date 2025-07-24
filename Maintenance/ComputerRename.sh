#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 06-01-23  ###
### Updated: 07-24-25  ###
### Version: 3.0       ###
##########################

readonly currentName=$(/usr/sbin/scutil --get LocalHostName)
readonly computerSerial=$(ioreg -l | grep IOPlatformSerialNumber | sed 's/"$//' | sed 's/.*"//')
readonly serialShort=${computerSerial: -6}
readonly logPath='/var/log/computerRename_Background.log'
standardName="SLU-$serialShort"

# Append current status to log file
function log_Message() {
    local timestamp="$(date "+%F %T")"
    printf "Log: %s %s\n" "$timestamp" "$1" | tee -a "$logPath"
}

# Validate serial number
function serial_Check() {
    if [[ -z "$computerSerial" ]];
    then
        log_Message "ERROR: Could not retrieve serial number"
        return 1
    elif [[ ${#computerSerial} -lt 6 ]];
    then
        log_Message "ERROR: Serial number too short: \"$computerSerial\""
        return 1
    else
        log_Message "Valid serial number found: \"$serialShort\""
        return 0
    fi
}

# Contains scutil commands to change device name
function rename_Device() {
    local name="$1"
    if [[ -n "$name" ]];
    then
        /usr/sbin/scutil --set ComputerName "$name"
        /usr/sbin/scutil --set LocalHostName "$name"
        /usr/sbin/scutil --set HostName "$name"
        /usr/local/bin/jamf recon	
    else
        log_Message "ERROR: Name is empty"
        exit 1
    fi
}

function main() {
    printf "Log: $(date "+%F %T") Beginning Computer Rename Background script\n" | tee "$logPath"

    log_Message "Checking for valid serial"
    if ! serial_Check;
    then
        log_Message "ERROR: Exiting at serial check"
        exit 1
    fi

    # If the current device name contains "Mac",
    # rename it using the SLU standard.
    if [[ $currentName == *"Mac"* ]];
    then
        log_Message "Device name contains Mac: \"$currentName\""
        log_Message "Renaming device: \"$standardName\""
        rename_Device "$standardName"

    # If the current device name already contains two hyphens,
    # rename it using the pre-existing prefix and the final six characters of the serial number,
    # exiting if the name is already correct.
    elif [[ $currentName == *-*-* ]];
    then
        longPrefix=$(echo "$currentName" | sed 's/\(.*-\).*$/\1/')
        log_Message "Device name contains a double prefix: \"$longPrefix\""
        newLongName="${longPrefix}${serialShort}"
        if [[ $currentName == $newLongName ]];
        then
            log_Message "Device already named correctly: \"$currentName\""
        else
            log_Message "Current computer name contains hyphens, \"$currentName\" with prefix \"$longPrefix\""
            log_Message "Renaming device: \"$newLongName\""
            rename_Device "$newLongName"
        fi

    # If the current device name already contains a hyphen,
    # rename it using the pre-existing prefix and the final six characters of the serial number,
    # exiting if the name is already correct.
    elif [[ $currentName == *"-"* ]];
    then
        prefix=$(echo "$currentName" | sed 's/\(.*-\).*/\1/')
        log_Message "Device name contains a prefix: \"$prefix\""
        newName="${prefix}${serialShort}"
        if [[ $currentName == $newName ]];
        then
            log_Message "Device already named correctly: \"$currentName\""
        else
            log_Message "Current computer name contains a hyphen, \"$currentName\" with prefix \"$prefix\""
            log_Message "Renaming device: \"$newName\""
            rename_Device "$newName"
        fi

    # If the current device name fails to match any conditions,
    # rename it using the SLU standard.
    else
        log_Message "Current computer name matches no critera: \"$currentName\""
        log_Message "Renaming device: \"$standardName\""
        rename_Device "$standardName"
    fi

    exit 0
}

main

