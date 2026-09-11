#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 09-09-26   ###
###  Updated: 09-11-26   ###
###  Version: 1.2        ###
############################

readonly scriptName='fix_MDMEnrollment'
readonly logFile="${HOME}/Desktop/${scriptName}.log"
readonly scriptDir="$(cd "$(dirname "$0")" && pwd)"
readonly remoteScriptPath='/tmp/remote_Fix_MDMEnrollment.sh'
readonly remoteLogPath='/tmp/remote_Fix_MDMEnrollment.out'
readonly localAdmin="$1"
readonly pass="$2"
readonly csvFile="$3"
readonly sshKey="$4"
readonly sshKeyPUBLIC="${sshKey}.pub"

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

# Info on how to run the script
function print_Usage() {
    cat <<EOF
Usage:
  bash $(basename "$0") [args]

Required Arguments:
  '\$1'              Local Admin Account Name
  '\$2'              Local Admin Account Pass 
  '\$3'              Local CSV file
  '\$4'              SSH key path

  bash $(basename "$0") "accountName" "accountPass" "csvFile" "sshKey"
EOF
}

function check_Arguments() {
    if [[ -z "$localAdmin" ]] || [[ -z "$pass" ]] || [[ -z "$csvFile" ]] || [[ -z "$sshKey" ]];
    then
        log_Message "Missing argument(s)" "ERROR"
        [[ -n "$localAdmin" ]] || log_Message "Missing Local Admin account name"
        [[ -n "$pass" ]] || log_Message "Missing Local Admin pass"
        [[ -n "$csvFile" ]] || log_Message "Missing path to CSV with device names"
        [[ -n "$sshKey" ]] || log_Message "Missing path to SSH key"
        print_Usage
        exit 1
    fi
}

function check_Connection() {
    local computer="$1"
    ping -c 1 -W 2 "$computer" >/dev/null 2>&1
    return $?
}

function main() {
	printf "Beginning ${scriptName} script\n" > "$logFile"

    check_Arguments

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

        "${scriptDir}/setup.expect" "$localAdmin" "$pass" "$computerConnection" "$sshKey" "$sshKeyPUBLIC"

        sleep 1

        if { printf '%s\n' "$pass"; cat "${scriptDir}/remote_Fix_MDMEnrollment.sh"; } \
            | ssh -i "$sshKey" -o IdentitiesOnly=yes "${localAdmin}@${computerConnection}" \
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
