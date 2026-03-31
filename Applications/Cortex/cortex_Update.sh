#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 03-19-26  ###
### Updated: 03-31-26  ###
### Version: 1.3       ###
##########################

pw="$4"
readonly jamfTrigger="$5"
readonly jamfFallbackTrigger="$6"
readonly jamfInstallVersion="$7"
readonly jamfFallbackVersion="$8"
readonly appName='Cortex XDR'
readonly appNameVersion="${appName} ${jamfInstallVersion}"
readonly appNameFallbackVersion="${appName} ${jamfFallbackVersion}"
readonly cortexApplicationPath='/Applications/Cortex XDR.app'
readonly cortexLibraryPath='/Library/Application Support/PaloAltoNetworks/Traps/bin'
readonly cortexUninstallerTool="${cortexLibraryPath}/cortex_xdr_uninstaller_tool"
readonly trapsUninstallerTool="${cortexLibraryPath}/traps_uninstaller_tool"
readonly cytoolPath="${cortexLibraryPath}/cytool"
readonly installWait=10
readonly logFile="/var/log/cortex_Update-${jamfInstallVersion}.log"

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

# Check for Cortex application
function app_Check(){
    [[ -d "$cortexApplicationPath" ]]
}

# Check for cytool, check-in if available
function cytool_Checkin() {
    if [[ -f "$cytoolPath" ]];
    then
        log_Message "Successfully located: ${cytoolPath}"
        if "$cytoolPath" checkin &>/dev/null;
        then
            log_Message "cytool check-in successful"
        else
            log_Message "Unable to check-in using cytool" "WARN"
            log_Message "Attempting cytool reconnect"
            if "$cytoolPath" reconnect &>/dev/null;
            then
                log_Message "cytool reconnect successful"
            else
                log_Message "Unable to reconnect using cytool" "ERROR"
            fi
        fi
    else
        log_Message "Unable to locate: \"${cytoolPath}\"" "ERROR"
    fi
}

# Set pw to random chars and then unset pw
function clean_Env() {
    if [[ -n "$pw" ]];
    then
        pw=$(head -c ${#pw} /dev/zero | tr '\0' 'X')
    fi
    unset pw
}

function main() {
    trap "clean_Env" EXIT INT TERM HUP

    if [[ -z "$pw" ]] || [[ -z "$jamfTrigger" ]] || [[ -z "$jamfFallbackTrigger" ]] || [[ -z "$jamfInstallVersion" ]] || [[ -z "$jamfFallbackVersion" ]];
    then
        log_Message "Arguments not provided" "ERROR"
        [[ -n "$pw" ]] || log_Message "Missing PW"
        [[ -n "$jamfTrigger" ]] || log_Message "Missing Cortex Trigger"
        [[ -n "$jamfFallbackTrigger" ]] || log_Message "Missing Cortex Fallback Trigger"
        [[ -n "$jamfInstallVersion" ]] || log_Message "Missing Cortex Version"
        [[ -n "$jamfFallbackVersion" ]] || log_Message "Missing Cortex Fallback Version"
        exit 1
    fi

    printf "Log: $(date "+%F %T") Beginning ${appNameVersion} Upgrade script\n" | tee "$logFile"

    if ! app_Check; 
    then
        log_Message "Unable to locate: ${cortexApplicationPath}"
    else
        log_Message "Application present: ${cortexApplicationPath}"
        echo "$pw" | sudo -S "$cytoolPath" security_modules disable self_prot
        log_Message "Attempted to disable SelfProt"
    fi
    
    log_Message "Installing ${appNameVersion}"
    if /usr/local/bin/jamf policy -event "$jamfTrigger" &>/dev/null;
    then
        log_Message "Successfully installed: ${appNameVersion}"
        sleep $installWait
        if app_Check;
        then
            log_Message "Application present: ${cortexApplicationPath}"
        else
            log_Message "Unable to locate: ${cortexApplicationPath}" "ERROR"
            if /usr/local/bin/jamf policy -event "$jamfFallbackTrigger" &>/dev/null;
            then
                log_Message "Successfully installed: ${appNameFallbackVersion}"
            else
                log_Message "Unable to install: ${appNameFallbackVersion}" "ERROR"
                exit 1
            fi
        fi
    else
        log_Message "Unable to install: ${appNameVersion}" "ERROR"
        if /usr/local/bin/jamf policy -event "$jamfFallbackTrigger" &>/dev/null;
        then
            log_Message "Successfully installed: ${appNameFallbackVersion}"
        else
            log_Message "Unable to install: ${appNameFallbackVersion}" "ERROR"
            exit 1
        fi
    fi

    sleep $installWait

    log_Message "Attempting to check-in with ${appName}"
    cytool_Checkin
    log_Message "${appNameVersion} upgrade finished"
    exit 0
}

main

