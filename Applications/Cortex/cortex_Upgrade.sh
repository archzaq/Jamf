#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 08-18-25  ###
### Updated: 08-18-25  ###
### Version: 1.0       ###
##########################

pw="$4"
readonly cortexApplicationPath='/Applications/Cortex XDR.app'
readonly cortexLibraryPath='/Library/Application Support/PaloAltoNetworks/Traps/bin'
readonly cortexUninstallerTool="${cortexLibraryPath}/cortex_xdr_uninstaller_tool"
readonly trapsUninstallerTool="${cortexLibraryPath}/traps_uninstaller_tool"
readonly cytoolPath="${cortexLibraryPath}/cytool"
readonly jamfInstall='Cortex_Install-8.8'
readonly logFile='/var/log/cortex_Upgrade.log'

# Append current status to log file
function log_Message() {
    local timestamp="$(date "+%F %T")"
    printf "Log: %s %s\n" "$timestamp" "$1" | tee -a "$logFile"
}

# Check for Cortex uninstaller, if found, run uninstaller
function check_Uninstall() {
    local path="$1"
    local name="$2"
    if [[ -f "$path" ]];
    then
        log_Message "${name} uninstaller found: ${path}"
        if "$path" "$pw" &>/dev/null;
        then
            log_Message "Successfully uninstalled: ${name}"
        else
            log_Message "ERROR: Unable to uninstall: ${name}"
            return 1
        fi
    else
        log_Message "Unable to locate: ${name}"
    fi
    return 0
}

# Check for cytool, check-in if available
function cytool_Checkin() {
    if [[ -f "$cytoolPath" ]];
    then
        log_Message "cytool found: ${cytoolPath}"
        if "$cytoolPath" checkin &>/dev/null;
        then
            log_Message "cytool check-in successful"
        else
            log_Message "Unable to check-in using cytool"
            log_Message "Attempting to reconnect"
            if "$cytoolPath" reconnect &>/dev/null;
            then
                log_Message "cytool reconnect successful"
            else
                log_Message "Unable to reconnect using cytool"
            fi
        fi
    else
        log_Message "ERROR: Unable to locate cytool: ${cytoolPath}"
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
    pw=''
    unset pw
}

function main() {
    trap "clean_Env" EXIT INT TERM HUP

    if [[ -z "$pw" ]];
    then
        log_Message "ERROR: Argument not provided"
        exit 1
    fi

    printf "Log: $(date "+%F %T") Beginning Cortex 8.8 Upgrade script\n" | tee "$logFile"

    if [[ ! -d "$cortexApplicationPath" ]];
    then
        log_Message "Unable to locate Cortex XDR application"
    else
        log_Message "Cortex XDR application located: ${cortexApplicationPath}"
        if [[ ! -f "$cortexUninstallerTool" ]] && [[ ! -f "$trapsUninstallerTool" ]];
        then
            log_Message "ERROR: Unable to locate Cortex or Traps Uninstaller Tool"
            exit 1
        fi

        if [[ ! -d "$cortexLibraryPath" ]];
        then
            log_Message "ERROR: Unable to locate Cortex XDR Library folder"
            exit 1
        fi

        if ! check_Uninstall "$cortexUninstallerTool" "Cortex XDR";
        then
            log_Message "ERROR: Exiting at Cortex XDR uninstall"
            exit 1
        fi

        if ! check_Uninstall "$trapsUninstallerTool" "Traps";
        then
            log_Message "ERROR: Exiting at Traps uninstall"
            exit 1
        fi

        sleep 5

        if app_Check;
        then
            log_Message "Cortex XDR application present: ${cortexApplicationPath}"
            exit 1
        else
            log_Message "Passed Cortex XDR application check, Cortex XDR removed"
        fi
    fi
    
    log_Message "Installing Cortex XDR 8.8"
    if /usr/local/bin/jamf policy -event "$jamfInstall" &>/dev/null;
    then
        log_Message "Cortex XDR successfully installed"
    else
        log_Message "ERROR: Unable to install Cortex XDR"
        exit 1
    fi

    sleep 10

    if ! app_Check;
    then
        log_Message "Unable to locate Cortex XDR application: ${cortexApplicationPath}"
        exit 1
    else
        log_Message "Passed Cortex XDR application check, Cortex XDR installed"
    fi

    log_Message "Attempting Cortex XDR check-in"
    cytool_Checkin

    log_Message "Cortex XDR 8.8 upgrade completed successfully"
    exit 0
}

main

