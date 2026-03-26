#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 03-19-26  ###
### Updated: 03-19-26  ###
### Version: 1.0       ###
##########################

pw="$4"
readonly jamfInstall="$5"
readonly jamfFallbackInstall="$6"
readonly appName='Cortex XDR'
readonly oldAppName='Traps'
readonly appNameVersion="${appName} 9.1"
readonly appNameFallbackVersion="${appName} 8.8"
readonly cortexApplicationPath='/Applications/Cortex XDR.app'
readonly cortexLibraryPath='/Library/Application Support/PaloAltoNetworks/Traps/bin'
readonly cortexUninstallerTool="${cortexLibraryPath}/cortex_xdr_uninstaller_tool"
readonly trapsUninstallerTool="${cortexLibraryPath}/traps_uninstaller_tool"
readonly cytoolPath="${cortexLibraryPath}/cytool"
readonly uninstallWait=5
readonly installWait=10
readonly logFile='/var/log/cortex_Upgrade-9.1.log'

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

# Check for Cortex uninstaller, if found, run uninstaller
function check_Uninstall() {
    local path="$1"
    local name="$2"
    if [[ -f "$path" ]];
    then
        log_Message "Uninstaller found: ${path}"
        if "$path" "$pw" &>/dev/null;
        then
            log_Message "Successfully uninstalled: ${name}"
        else
            log_Message "Unable to uninstall: ${name}" "ERROR"
            return 1
        fi
    else
        log_Message "Unable to locate: \"${name}\"" "WARN"
    fi
    return 0
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

# Check for Cortex application
function app_Check(){
    if [[ -d "$cortexApplicationPath" ]];
    then
        return 0
    else
        return 1
    fi
}

function clean_Env() {
    if [[ -n "$pw" ]];
    then
        pw=$(head -c ${#pw} /dev/zero | tr '\0' 'X')
    fi
    unset pw
}

function main() {
    trap "clean_Env" EXIT INT TERM HUP

    if [[ -z "$pw" ]] || [[ -z "$jamfInstall" ]] || [[ -z "$jamfFallbackInstall" ]];
    then
        log_Message "Arguments not provided" "ERROR"
        exit 1
    fi

    printf "Log: $(date "+%F %T") Beginning ${appNameVersion} Upgrade script\n" | tee "$logFile"

    if [[ ! -d "$cortexApplicationPath" ]];
    then
        log_Message "Unable to locate: ${cortexApplicationPath}"
    else
        log_Message "Application present: ${cortexApplicationPath}"
        if [[ ! -f "$cortexUninstallerTool" ]] && [[ ! -f "$trapsUninstallerTool" ]];
        then
            log_Message "Unable to locate \"${cortexUninstallerTool}\" or \"${trapsUninstallerTool}\"" "WARN"
        fi
        if echo "$pw" | sudo -S "$cytoolPath" self_prot disable;
        then
            log_Message "SelfProt disabled successful"
        else
            log_Message "Unable to disable SelfProt" "WARN"
        fi
    fi
    
    log_Message "Installing ${appNameVersion}"
    if /usr/local/bin/jamf policy -event "$jamfInstall" &>/dev/null;
    then
        log_Message "Successfully installed: ${appNameVersion}"
        sleep $installWait
        if app_Check;
        then
            log_Message "Application present: ${cortexApplicationPath}"
        else
            log_Message "Unable to locate: ${cortexApplicationPath}" "ERROR"
            if /usr/local/bin/jamf policy -event "$jamfFallbackInstall" &>/dev/null;
            then
                log_Message "Successfully installed: ${appNameFallbackVersion}"
            else
                log_Message "Unable to install: ${appNameFallbackVersion}" "ERROR"
                exit 1
            fi
        fi
    else
        log_Message "Unable to install: ${appNameVersion}" "ERROR"
        if /usr/local/bin/jamf policy -event "$jamfFallbackInstall" &>/dev/null;
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

