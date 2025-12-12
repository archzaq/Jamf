#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 06-01-23  ###
### Updated: 12-11-25  ###
### Version: 3.1       ###
##########################

readonly currentName=$(/usr/sbin/scutil --get LocalHostName)
readonly currentHostName=$(/usr/sbin/scutil --get HostName)
readonly currentComputerName=$(/usr/sbin/scutil --get ComputerName)
readonly computerSerial=$(ioreg -l | grep IOPlatformSerialNumber | sed 's/"$//' | sed 's/.*"//')
readonly serialShort=${computerSerial: -6}
readonly logPath='/var/log/computerRename_Background.log'
standardName="SLU-$serialShort"

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

# Validate serial number
function serial_Check() {
    if [[ -z "$computerSerial" ]];
    then
        log_Message "Could not retrieve serial number" "ERROR"
        return 1
    elif [[ ${#computerSerial} -lt 6 ]];
    then
        log_Message "Serial number too short: \"$computerSerial\"" "ERROR"
        return 1
    else
        log_Message "Valid serial number found: \"$serialShort\""
        return 0
    fi
}

function check_NamesMatch() {
    log_Message "Checking name consistency"
    if [[ "$currentName" != "$currentHostName" ]] || [[ "$currentName" != "$currentComputerName" ]];
    then
        log_Message "Name mismatch, standardizing to: \"$currentName\""
        rename_Device "$currentName"
        log_Message "Names synchronized, continuing with normal rename"
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
        log_Message "Name is empty" "ERROR"
        exit 1
    fi
}

function main() {
    if [[ -w "$logFile" ]];
	then
		printf "Log: $(date "+%F %T") Beginning Automated Computer Rename script\n" | tee "$logFile"
	else
		printf "Log: $(date "+%F %T") Beginning Automated Computer Rename script\n"
	fi

    log_Message "Checking for valid serial"
    if ! serial_Check;
    then
        log_Message "Exiting at serial check" "ERROR"
        exit 1
    fi

    check_NamesMatch

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

