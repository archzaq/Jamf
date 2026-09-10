#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 09-09-26   ###
###  Updated: 09-10-26   ###
###  Version: 1.0        ###
############################

readonly scriptName='fix_MDMEnrollment'
readonly logFile="/var/log/${scriptName}.log"
readonly localAdmin=''
readonly pass=''
readonly csvFile='test.csv'
readonly scriptDir="$(cd "$(dirname "$0")" && pwd)"
readonly remoteScriptPath='/tmp/remote_Fix_MDMEnrollment.sh'
readonly remoteLogPath='/tmp/remote_Fix_MDMEnrollment.out'

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

# Check if someone is logged into the device
function check_Login() {
	if [[ "$currentUser" == 'loginwindow' ]] || [[ -z "$currentUser" ]] || [[ "$currentUser" == 'root' ]];
	then
		log_Message "No one currently logged in"
		return 1
	else
		log_Message "${currentUser} currently logged in"
		return 0
	fi
}

function check_Connection() {
    local computer="$1"
    ping -c 1 -W 2 "$computer" >/dev/null 2>&1
    return $?
}

function main() {
	: > "$logFile" 2>/dev/null
	log_Message "Beginning ${scriptName} script"

    while IFS=, read -r -u 3 computerName ip 
    do
        [[ "$computerName" == *"Computer Name"* ]] && continue
        if ! check_Connection "$computerName";
        then
            log_Message "Unable to contact ${computerName} by hostname, trying by IP" "ERROR"
            if ! check_Connection "$ip";
            then
                log_Message "Unable to contact ${computerName} at ${ip}, skipping" "ERROR"
                continue
            else
                computerConnection="${ip%$'\r'}"
            fi
        else
            computerConnection="${computerName%$'\r'}"
        fi

        "${scriptDir}/setup_Expect.expect" "$localAdmin" "$pass" "$computerConnection"

        sleep 1

        if { printf '%s\n' "$pass"; cat "${scriptDir}/remote_Fix_MDMEnrollment.sh"; } \
            | ssh -i "/Users/arch/.ssh/mdmrenew" -o IdentitiesOnly=yes "${localAdmin}@${computerConnection}" \
                "sudo -S -p '' /bin/bash -c 'cat > ${remoteScriptPath} && chmod 700 ${remoteScriptPath} && { nohup ${remoteScriptPath} >${remoteLogPath} 2>&1 </dev/null & }'";
        then
            log_Message "Enrollment script launched on ${computerConnection}"
        else
            log_Message "Failed to launch enrollment script on ${computerConnection}" "ERROR"
        fi

    done 3< "$csvFile"

    exit 0
}

main
