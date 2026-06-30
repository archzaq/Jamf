#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 06-20-26   ###
###  Updated: 06-30-26   ###
###  Version: 1.0        ###
############################

readonly token="$4"
readonly scriptName='uninstall_Cyberark'
readonly logFile="/var/log/${scriptName}.log"
readonly cyberarkPath='/Applications/CyberArk EPM.app'
readonly cyberarkUninstaller="${cyberarkPath}/Contents/MacOS/CyberArkEPMUninstall"
readonly cyberarkUninstallHelper="${cyberarkPath}/Contents/Helpers/CyberArkEPMUninstall"

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
	printf "Log: $(date "+%F %T") Beginning ${scriptName} script\n" | tee "$logFile"

    [[ -z "$token" ]] && { log_Message "No token provided" "ERROR"; exit 1; }

    if [[ -d "$cyberarkPath" ]];
    then
        log_Message "Checking for CyberArk uninstaller"
        if [[ -e "$cyberarkUninstaller" ]];
        then
            "$cyberarkUninstaller" -token "$token" || { log_Message "Uninstaller failed!" "ERROR"; exit 1; }
            log_Message "Successfully uninstalled CyberArk!"
        elif [[ -e "$cyberarkUninstallHelper" ]];
        then
            "$cyberarkUninstallHelper" -token "$token" || { log_Message "Uninstaller failed!" "ERROR"; exit 1; }
            log_Message "Successfully uninstalled CyberArk!"
        else
            log_Message "No uninstaller present! Check ${cyberarkPath} and try again, or manually run the uninstaller" "ERROR"
            exit 1
        fi

        if [[ -d "$cyberarkPath" ]];
        then
            log_Message "CyberArk still present! Check ${cyberarkPath} and try again, or manually run the uninstaller" "ERROR"
            exit 1
        else
            log_Message "Exiting successfully!"
        fi
    else
        log_Message "CyberArk not found, exiting" "WARN"
    fi

    exit 0
}

main
