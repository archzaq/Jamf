#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 03-19-26  ###
### Updated: 03-31-26  ###
### Version: 1.4       ###
##########################

pw="$4"
readonly appName='Cortex XDR'
readonly oldAppName='Traps'
readonly cortexApplicationPath='/Applications/Cortex XDR.app'
readonly cortexLibraryPath='/Library/Application Support/PaloAltoNetworks/Traps/bin'
readonly cortexUninstallerTool="${cortexLibraryPath}/cortex_xdr_uninstaller_tool"
readonly trapsUninstallerTool="${cortexLibraryPath}/traps_uninstaller_tool"
readonly cytoolPath="${cortexLibraryPath}/cytool"
readonly logFile='/var/log/cortex_Uninstall.log'
readonly uninstallWait=5

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
        echo "$pw" | sudo -S "$path"
        log_Message "Attempted uninstall"
    else
        log_Message "Unable to locate: \"${name}\"" "WARN"
        return 1
    fi
    return 0
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

    printf "Log: $(date "+%F %T") Beginning Cortex Uninstall script\n" | tee "$logFile"

    if [[ -z "$pw" ]];
    then
        log_Message "Argument not provided" "ERROR"
        exit 1
    fi

    if [[ ! -d "$cortexApplicationPath" ]];
    then
        log_Message "Unable to locate: ${cortexApplicationPath}"
    else
        log_Message "Application present: ${cortexApplicationPath}"
        if [[ ! -d "$cortexLibraryPath" ]];
        then
            log_Message "Unable to locate: \"${cortexLibraryPath}\"" "ERROR"
            exit 1
        fi

        if [[ ! -f "$cortexUninstallerTool" ]] && [[ ! -f "$trapsUninstallerTool" ]];
        then
            log_Message "Unable to locate \"${cortexUninstallerTool}\" or \"${trapsUninstallerTool}\"" "ERROR"
            exit 1
        fi

        if ! check_Uninstall "$cortexUninstallerTool" "$appName";
        then
            log_Message "Skipping ${appName} uninstall" "WARN"
        fi

        if ! check_Uninstall "$trapsUninstallerTool" "$oldAppName";
        then
            log_Message "Skipping ${oldAppName} uninstall" "WARN"
        fi

        sleep $uninstallWait

        if app_Check;
        then
            log_Message "Application still present: ${cortexApplicationPath}"
            exit 1
        else
            log_Message "Successfully removed: ${cortexApplicationPath}"
        fi
    fi

    exit 0
}

main

