#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 06-26-25  ###
### Updated: 06-26-25  ###
### Version: 1.0       ###
##########################

# Check if Jamf binary exists to determine which parameters to use
if [[ -f "/usr/local/jamf/bin/jamf" ]];
then
    readonly userFolder="$4"
    readonly fileName="$5"
else
    readonly userFolder="$1"
    readonly fileName="$2"
fi

readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly folderLocation="/Users/$currentUser/$userFolder"
readonly fileLocation="${folderLocation}/${fileName}"
readonly logPath='/var/log/quarantine_Removal.log'

# Append current status to log file
function log_Message() {
    printf "Log: $(date "+%F %T") %s\n" "$1" | tee -a "$logPath"
}

# Ensure arguments are passed
function arg_Check() {
    if [[ -z "$userFolder" ]] || [[ -z "$fileName" ]]; 
    then
        log_Message "ERROR: Missing critical arguments"
        exit 1
    fi
}

# Check if someone is logged into the device
function login_Check() {
    if [[ "$currentUser" == 'loginwindow' ]] || [[ -z "$currentUser" ]] || [[ "$currentUser" == 'root' ]];
    then
        log_Message "No one currently logged in"
        return 1
    else
        log_Message "${currentUser} currently logged in"
        return 0
    fi
}

function main() {
    arg_Check
    printf "Log: $(date "+%F %T") Beginning Quarantine Removal script.\n" | tee "$logPath"

    if ! login_Check;
    then
        log_Message "Exiting for invalid user logged in."
        exit 1
    fi

    log_Message "Checking in folder: ${folderLocation}"
    found=0
    for app in "$fileLocation"*;
    do
        if [[ -e "$app" ]];
        then
            found=1
            log_Message "Found ${app}"
            if xattr -l "$app" 2>/dev/null | grep -q "com.apple.quarantine";
            then
                if xattr -r -d com.apple.quarantine "$app" 2>/dev/null;
                then
                    log_Message "SUCCESS: Removed quarantine from ${app}"
                else
                    log_Message "ERROR: Failed to remove quarantine from ${app}"
                    exit 1
                fi
            else
                log_Message "INFO: ${app} is not quarantined"
            fi
        fi
    done

    if [[ "$found" -eq 0 ]];
    then
        log_Message "No file found starting with ${fileName} in ${folderLocation}"
        exit 1
    fi

    exit 0
}

main

