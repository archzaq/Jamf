#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 09-10-25  ###
### Updated: 09-11-25  ###
### Version: 1.0       ###
##########################

readonly licenseServer="$4"
readonly SPSSPath='/Applications/IBM SPSS Statistics'
readonly SPSSAppPath="${SPSSPath}/IBM SPSS Statistics.app"
readonly SPSSAppPathTemp="${SPSSPath}/SPSS Statistics.app"
readonly SPSSActivationPath="${SPSSPath}/Resources/Activation"
readonly licenseActivator="${SPSSActivationPath}/licenseactivator"
readonly activationProperties="${SPSSActivationPath}/activation.properties"
readonly logFile='/var/log/set_SPSSLicense.log'

# Append current status to log file
function log_Message() {
    local message="$1"
    local type="${2:-Log}"
    local timestamp="$(date "+%F %T")"
    local formattedMessage
    formattedMessage=$(printf "%s: %s %s\n" "$type" "$timestamp" "$message")
    if [[ -w "$logFile" ]];
    then
        printf "%s" "$formattedMessage" | tee -a "$logFile"
    else
        printf "%s" "$formattedMessage"
    fi
}

function check_SPSSInstalled() {
    if [[ -d "$SPSSAppPath" ]];
    then
        log_Message "SPSS located: ${SPSSPath}"
    else
        log_Message "Unable to locate SPSS" "WARN"
        if [[ -d "$SPSSPath" ]];
        then
            log_Message "Able to locate the SPSS folder in Applications, but no SPSS Application" "WARN"
        fi
        return 1
    fi
    return 0
}

function rename_SPSSApplication() {
    local start="$1"
    local end="$2"
    if mv "$start" "$end";
    then
        log_Message "SPSS renamed from ${start} to ${end}"
    else
        log_Message "Unable to rename SPSS from ${start} to ${end}" "WARN"
        return 1
    fi
    return 0
}

function change_LicenseServer() {
    if [[ -f "$activationProperties" ]];
    then
        currentServer=$(grep '^LSHOST=' "$activationProperties" | awk -F '=' '{print $2}')
        if [[ "$currentServer" == "$licenseServer" ]];
        then
            log_Message "License server already set to ${licenseServer}"
        else
            log_Message "Changing license server from ${currentServer} to ${licenseServer}"
            sed -i '' -e "s/^LSHOST=.*/LSHOST=${licenseServer}/" "$activationProperties"
        fi
        currentServer=$(grep '^LSHOST=' "$activationProperties" | awk -F '=' '{print $2}')
        if [[ "$currentServer" == "$licenseServer" ]];
        then
            log_Message "License server properly set"
            return 0
        else
            log_Message "Unable to verify license server was changed" "WARN"
        fi
    else
        log_Message "${activationProperties} does not exist" "WARN"
    fi
    return 1
}

function clean_Env() {
    if [[ -d "$SPSSAppPathTemp" ]];
    then
        log_Message "SPSS still named improperly, renaming back to original name" "WARN"
        if ! rename_SPSSApplication "$SPSSAppPathTemp" "$SPSSAppPath";
        then
            log_Message "Unable to rename SPSS from ${SPSSAppPathTemp} to ${SPSSAppPath}" "ERROR"
        fi
    elif [[ -d "$SPSSAppPath" ]];
    then
        log_Message "SPSS already named properly"
    else
        log_Message "Unable to locate SPSS" "ERROR"
    fi
}

function main() {
    trap "clean_Env" INT TERM HUP EXIT
    printf "Log: $(date "+%F %T") Beginning Set SPSS License script\n" | tee "$logFile"

    if [[ -z "$licenseServer" ]];
    then
        log_Message "Missing critical arguments" "ERROR"
        exit 1
    fi

    if ! check_SPSSInstalled;
    then
        log_Message "Exiting at SPSS Application check" "ERROR"
        exit 1
    fi

    if ! rename_SPSSApplication "$SPSSAppPath" "$SPSSAppPathTemp";
    then
        log_Message "Exiting at SPSS rename" "ERROR"
        exit 1
    fi

    if ! change_LicenseServer;
    then
        log_Message "Exiting at change license server" "ERROR"
        exit 1
    fi

    if "$licenseActivator" -f "$activationProperties";
    then
        log_Message "License server set for SPSS using license activator"
    else
        log_Message "Unable to set license server" "ERROR"
        exit 1
    fi

    if ! rename_SPSSApplication "$SPSSAppPathTemp" "$SPSSAppPath";
    then
        log_Message "Exiting at SPSS rename" "ERROR"
        exit 1
    fi

    log_Message "Process completed successfully"
    exit 0
}

main
