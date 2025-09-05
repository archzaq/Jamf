#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 08-18-25  ###
### Updated: 09-05-25  ###
### Version: 1.2       ###
##########################

pw="$4"
readonly appName='Cortex XDR'
readonly oldAppName='Traps'
readonly appNameVersion="${appName} 8.8"
readonly appNameFallbackVersion="${appName} 8.5.1"
readonly cortexApplicationPath='/Applications/Cortex XDR.app'
readonly cortexLibraryPath='/Library/Application Support/PaloAltoNetworks/Traps/bin'
readonly cortexUninstallerTool="${cortexLibraryPath}/cortex_xdr_uninstaller_tool"
readonly trapsUninstallerTool="${cortexLibraryPath}/traps_uninstaller_tool"
readonly cytoolPath="${cortexLibraryPath}/cytool"
readonly uninstallWait=5
readonly installWait=10
readonly jamfInstall='Cortex_Install-8.8'
readonly jamfFallbackInstall='Cortex_Install-8.5.1'
readonly logFile='/var/log/cortex_Upgrade.log'

# Append current status to log file
function log_Message() {
    local message="$1"
    local logType="${2:-Log}"
    local timestamp="$(date "+%F %T")"
    printf "%s: %s %s\n" "$logType" "$timestamp" "$message" | tee -a "$logFile"
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

    if [[ -z "$pw" ]];
    then
        log_Message "Argument not provided" "ERROR"
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
            log_Message "Unable to locate \"${cortexUninstallerTool}\" or \"${trapsUninstallerTool}\"" "ERROR"
            exit 1
        fi

        if [[ ! -d "$cortexLibraryPath" ]];
        then
            log_Message "Unable to locate: \"${cortexLibraryPath}\"" "ERROR"
            exit 1
        fi

        if ! check_Uninstall "$cortexUninstallerTool" "$appName";
        then
            log_Message "Exiting at ${appName} uninstall" "ERROR"
            exit 1
        fi

        if ! check_Uninstall "$trapsUninstallerTool" "$oldAppName";
        then
            log_Message "Exiting at ${oldAppName} uninstall" "ERROR"
            exit 1
        fi

        sleep $uninstallWait

        if app_Check;
        then
            log_Message "Application present: ${cortexApplicationPath}"
            exit 1
        else
            log_Message "Successfully removed: ${cortexApplicationPath}"
        fi
    fi
    
    log_Message "Installing ${appNameVersion}"
    if /usr/local/bin/jamf policy -event "$jamfInstall" &>/dev/null;
    then
        log_Message "Successfully installed: ${appNameVersion}"
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

    if app_Check;
    then
        log_Message "Application present: ${cortexApplicationPath}"
    else
        log_Message "Unable to locate: ${cortexApplicationPath}" "ERROR"
        exit 1
    fi

    log_Message "Attempting to check-in with ${appName}"
    cytool_Checkin
    log_Message "${appNameVersion} upgrade finished"
    exit 0
}

main

