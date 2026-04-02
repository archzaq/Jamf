#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 04-02-26   ###
###  Updated: 04-02-26   ###
###  Version: 0.1        ###
############################

readonly scriptName='install_MFClientUpdate'
readonly cleanAppName='PaperCut MF Client'
readonly mfClientTargetVersion='23.0.7.68939'
readonly mfClientAppPath='/Applications/PCClient.app'
readonly mfClientInfoPath="${mfClientAppPath}/Contents/Info.plist"
readonly logFile="/var/log/${scriptName}.log"

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

    log_Message "Checking for ${cleanAppName} at: ${mfClientAppPath}"
    if [[ -d "$mfClientAppPath" ]];
    then
        mfClientVersion="$(/usr/bin/defaults read "$mfClientInfoPath" CFBundleShortVersionString)"
        log_Message "${cleanAppName} version: ${mfClientVersion}"
        if [[ "$mfClientVersion" != "$mfClientTargetVersion" ]];
        then
            log_Message "Outdated version installed. ${mfClientVersion} instead of ${mfClientTargetVersion}. Installing the latest version"
            /usr/local/bin/jamf policy -event InstallMFClient
            if [[ -d "$mfClientAppPath" ]];
            then
                log_Message "${cleanAppName} installed!"
                log_Message "Checking ${cleanAppName} version again"
                mfClientVersion="$(/usr/bin/defaults read "$mfClientInfoPath" CFBundleShortVersionString)"
                log_Message "${cleanAppName} version: ${mfClientVersion}"
                if [[ "$mfClientVersion" != "$mfClientTargetVersion" ]];
                then
                    log_Message "Outdated version still installed. ${mfClientVersion} instead of ${mfClientTargetVersion}"
                    exit 1
                fi
            else
                log_Message "Unable to locate ${cleanAppName}" "ERROR"
                exit 1
            fi
        elif [[ "$mfClientVersion" == "$mfClientTargetVersion" ]];
        then
            log_Message "${cleanAppName} up to date!"
        else
            log_Message "Unable to determine ${cleanAppName} version: ${mfClientVersion}" "ERROR"
            exit 1
        fi
    else
        log_Message "Unable to locate ${cleanAppName}" "ERROR"
        exit 1
    fi
    
    exit 0
}

main
