#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 04-18-26   ###
###  Updated: 04-19-26   ###
###  Version: 1.0        ###
############################

readonly scriptName='disable_GlobalProtect_Autostart'
readonly logFile="/var/log/${scriptName}.log"
readonly panGPA_plist='/Library/LaunchAgents/com.paloaltonetworks.gp.pangpa.plist'
readonly panGPS_plist='/Library/LaunchAgents/com.paloaltonetworks.gp.pangps.plist'

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

# Set Global Protect plist values to false on the required keys
function update_PlistValue_ToFalse() {
    local plist="$1"
    local var="$2"
    local varStatus
    varStatus="$(/usr/bin/plutil -extract "$var" raw "$plist" 2>/dev/null)"
    case "$varStatus" in
        true)
            log_Message "${var} set to ${varStatus}, changing to false"
            if ! /usr/bin/plutil -replace "$var" -bool false "$plist";
            then
                log_Message "plutil failed to write ${var}" "WARN"
                return 1
            fi
            varStatus="$(/usr/bin/plutil -extract "$var" raw "$plist" 2>/dev/null)"
            if [[ "$varStatus" != "false" ]];
            then
                log_Message "Failed to set ${var} to false" "WARN"
                return 1
            fi
            ;;
        false)
            log_Message "${var} already set to false"
            ;;
        "")
            log_Message "${var} not present in plist, treating as default"
            ;;
        *)
            log_Message "Unexpected value for ${var}: ${varStatus}" "WARN"
            return 1
            ;;
    esac
    return 0
}

# Ensure old Global Protect plist is booted out to allow the app to quit
function bootout_LaunchAgent() {
    local serviceLabel="$1"
    local currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ { print $3 }')"
    if [[ -z "$currentUser" || "$currentUser" == "loginwindow" ]];
    then
        log_Message "No console user logged in, skipping bootout of ${serviceLabel}"
        return 0
    fi
    local consoleUID="$(/usr/bin/id -u "$currentUser")"
    if [[ -z "$consoleUID" ]];
    then
        log_Message "Unable to get UID for console user ${currentUser}" "WARN"
        return 1
    fi
    local serviceTarget="gui/${consoleUID}/${serviceLabel}"
    if ! /bin/launchctl print "$serviceTarget" &>/dev/null;
    then
        log_Message "${serviceLabel} not loaded in ${serviceTarget}, nothing to bootout"
        return 0
    fi
    log_Message "Booting out ${serviceTarget}"
    /bin/launchctl bootout "$serviceTarget"
    sleep 2
    if /bin/launchctl print "$serviceTarget" &>/dev/null;
    then
        log_Message "Failed to bootout ${serviceLabel}" "WARN"
        return 1
    fi
    return 0
}

function main() {
    printf "Log: $(date "+%F %T") Beginning ${scriptName} script\n" | tee "$logFile"

    if [[ "$(/usr/bin/id -u)" -ne 0 ]];
    then
        log_Message "Script must be run as root" "ERROR"
        exit 1
    fi

    if [[ ! -f "$panGPA_plist" ]];
    then
        log_Message "Unable to locate PanGPA plist file" "WARN"
    else
        log_Message "PanGPA plist located, getting RunAtLoad status"
        update_PlistValue_ToFalse "$panGPA_plist" "RunAtLoad"
        log_Message "Getting PanGPA KeepAlive status"
        update_PlistValue_ToFalse "$panGPA_plist" "KeepAlive"
        bootout_LaunchAgent "com.paloaltonetworks.gp.pangpa"
    fi

    if [[ ! -f "$panGPS_plist" ]];
    then
        log_Message "Unable to locate PanGPS plist file" "WARN"
    else
        log_Message "PanGPS plist located, getting RunAtLoad status"
        update_PlistValue_ToFalse "$panGPS_plist" "RunAtLoad"
    fi

    local globalProtect_pid="$(pgrep "GlobalProtect")"
    if [[ -n "$globalProtect_pid" ]];
    then
        log_Message "Killing GlobalProtect"
        killall "GlobalProtect"
        globalProtect_pid="$(pgrep "GlobalProtect")"
        if [[ -n "$globalProtect_pid" ]];
        then
            log_Message "Failed to kill GlobalProtect" "WARN"
        fi
    fi

    exit 0
}

main
