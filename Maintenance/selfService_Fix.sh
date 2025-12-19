#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 09-24-25  ###
### Updated: 09-25-25  ###
### Version: 1.0       ###
##########################

readonly logFile='/var/log/selfService_Fix.log'
readonly uuid="$(system_profiler SPHardwareDataType | awk '/UUID/ {print $3}')"
keychainsFound=0
keychainsRemoved=0

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
        printf "Log: $(date "+%F %T") Beginning Self Service Fix script\n" | tee "$logFile"
    else
        printf "Log: $(date "+%F %T") Beginning Self Service Fix script\n"
    fi

    for user in /Users/*;
    do
        if [[ -d "${user}/Library/Keychains" ]];
        then
            if [[ -d "${user}/Library/Keychains/${uuid}" ]];
            then
                ((keychainsFound++))
                log_Message "Removing ${uuid} keychain for ${user}"
                if rm -r "${user}/Library/Keychains/${uuid}";
                then
                    ((keychainsRemoved++))
                else
                    log_Message "Unable to remove ${uuid} keychain for ${user}" "ERROR"
                fi
            else
                log_Message "Keychain folder found, but none for ${uuid}" "WARN"
            fi
        fi
    done

    if [[ "$keychainsFound" -eq 0 ]];
    then
        log_Message "No keychains found" "WARN"
    elif [[ "$keychainsFound" -eq "$keychainsRemoved" ]];
    then
        log_Message "All keychains successfully removed!"
    elif [[ "$keychainsFound" -gt "$keychainsRemoved" ]];
    then
        log_Message "Keychains partially removed, check logs for persisting issues" "WARN"
    fi

    log_Message "Exiting!"

}

main

