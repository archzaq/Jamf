#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 00-00-00   ###
###  Updated: 00-00-00   ###
###  Version: 0.1        ###
############################

readonly scriptName='fix_MDMEnrollment'
readonly logFile="/var/log/${scriptName}.log"
readonly localAdmin=''
readonly pass=''
readonly csvFile='test.csv'

# Append current status to log file
function log_Message() {
	local message="$1"
	local type="${2:-Log}"
	local timestamp="$(date "+%F %T")"
	if [[ -f "$logFile" ]];
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
	printf "Log: $(date "+%F %T") Beginning ${scriptName} script\n" | tee "$logFile"

    while IFS=, read -r computerName ip
    do
        [[ "$computerName" == "Computer Name"* ]] && continue

        if ! check_Connection "$computerName";
        then
            log_Message "Unable to contact ${computerName} at ${ip}" "ERROR"
            exit 1
        fi



    done < "$csvFile"

    exit 0
}

main
