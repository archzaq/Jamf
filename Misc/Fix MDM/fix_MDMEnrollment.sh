#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 09-09-26   ###
###  Updated: 10-26-26   ###
###  Version: 1.8        ###
############################

readonly scriptName='fix_MDMEnrollment'
readonly logFile="${HOME}/Desktop/${scriptName}.log"
readonly collectedLogDir="${HOME}/Desktop/${scriptName}_Logs"
readonly summaryFile="${collectedLogDir}/summary.csv"
readonly scriptDir="$(cd "$(dirname "$0")" && pwd)"
readonly remoteScriptPath='/tmp/remote_Fix_MDMEnrollment.sh'
readonly remoteLogPath='/tmp/remote_Fix_MDMEnrollment.out'
readonly remoteScriptLog='/var/log/remote_Fix_MDMEnrollment.log'
readonly localAdmin="$1"
readonly pass="$2"
readonly csvFile="$3"
readonly sshKey="$4"
readonly sshKeyPUBLIC="${sshKey}.pub"
readonly runMode="$5"

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

Optional Arguments:
  '\$5'              --logs-only, collect the last run's logs without launching the enrollment script

  bash $(basename "$0") "accountName" "accountPass" "csvFile" "sshKey"
  bash $(basename "$0") "accountName" "accountPass" "csvFile" "sshKey" --logs-only
EOF
}

# Ensure all critial arguments are provided
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
    # Refuse anything unexpected so a typo never launches the enrollment script by mistake
    if [[ -n "$runMode" ]] && [[ "$runMode" != '--logs-only' ]];
    then
        log_Message "Unknown option: ${runMode}" "ERROR"
        print_Usage
        exit 1
    fi
}

# Ping a device
function check_Connection() {
    local computer="$1"
    ping -c 1 -t 2 "$computer" >/dev/null 2>&1
    return $?
}

# Check if an earlier enrollment script is still running on the device
# Returns 10 if running, 0 if not, anything else if the check itself failed
function remoteScript_Running() {
    local connection="$1"
    printf '%s\n' "$pass" | ssh -i "$sshKey" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o WarnWeakCrypto=no-pq-kex "${localAdmin}@${connection}" \
            "sudo -S -p '' /bin/bash -c 'if /usr/bin/pgrep -f \"^/bin/bash ${remoteScriptPath}\" >/dev/null; then exit 10; fi'"
    return $?
}

# Copy a file off the device as root, an empty local copy means it did not exist
function fetch_RemoteFile() {
    local connection="$1"
    local remotePath="$2"
    local localPath="$3"
    printf '%s\n' "$pass" | ssh -i "$sshKey" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o WarnWeakCrypto=no-pq-kex "${localAdmin}@${connection}" \
            "sudo -S -p '' /bin/bash -c 'if [[ -f ${remotePath} ]]; then cat ${remotePath}; fi'" > "$localPath"
    return $?
}

# Quote a value for the summary CSV
function csv_Field() {
    local quote='"'
    printf '"%s"' "${1//$quote/$quote$quote}"
}

# Read the outcome of the last run out of the collected logs and add it to the summary CSV
function add_SummaryRow() {
    local computer="$1"
    local connection="$2"
    local collectedLog="$3"
    local collectedOut="$4"
    local scriptRunning="$5"
    local lastRun=''
    local outcome='No previous run'
    local detail=''
    local mdmIdentity=''
    local scriptOutput=''

    if [[ -s "$collectedLog" ]];
    then
        lastRun="$(head -n 1 "$collectedLog" | awk '{ print $2, $3 }')"
        mdmIdentity="$(sed -n -E \
            -e 's/.*MDM identity expired on (.*)/\1 (expired)/p' \
            -e 's/.*MDM identity valid until (.*)/\1 (valid)/p' \
            -e 's/.*Jamf CA expired on (.*)/\1 (CA expired)/p' "$collectedLog" | head -n 1)"
    fi

    # The script logs everything itself, so anything in the nohup output is usually a crash
    if [[ -s "$collectedOut" ]];
    then
        scriptOutput="$(grep -v '^[[:space:]]*$' "$collectedOut" | tail -n 1)"
    fi

    if [[ "$scriptRunning" == true ]];
    then
        outcome='Running'
        detail="$(tail -n 1 "$collectedLog" | cut -d ' ' -f 4-)"
    elif [[ ! -s "$collectedLog" ]];
    then
        # Output without a log means the script died before it started logging
        if [[ -n "$scriptOutput" ]];
        then
            outcome='Crashed'
        fi
    elif grep -q 'Device successfully enrolled' "$collectedLog";
    then
        outcome='Enrolled'
    elif grep -q 'Device already reports an MDM enrollment' "$collectedLog";
    then
        outcome='Already enrolled'
    elif ! grep -q 'Exiting' "$collectedLog";
    then
        # No exit line and not running means it was killed before it could clean up
        outcome='Incomplete'
        detail="$(tail -n 1 "$collectedLog" | cut -d ' ' -f 4-)"
    else
        outcome='Failed'
        detail="$(grep -m 1 '^ERROR:' "$collectedLog" | cut -d ' ' -f 4-)"
    fi

    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$(csv_Field "$computer")" \
        "$(csv_Field "$connection")" \
        "$(csv_Field "$(date "+%F %T")")" \
        "$(csv_Field "$lastRun")" \
        "$(csv_Field "$outcome")" \
        "$(csv_Field "$mdmIdentity")" \
        "$(csv_Field "$detail")" \
        "$(csv_Field "$scriptOutput")" >> "$summaryFile"
    log_Message "Last run on ${connection}: ${outcome}${detail:+ (${detail})}"
    if [[ -n "$scriptOutput" ]];
    then
        log_Message "Script output on ${connection}: ${scriptOutput}" "WARN"
    fi
}

# Copy the log and nohup output from the last run off the device before a new run overwrites them
function collect_RemoteLogs() {
    local computer="$1"
    local connection="$2"
    local scriptRunning="$3"
    local stamp="$(date "+%F_%H%M%S")"
    local collectedLog="${collectedLogDir}/${computer}_${stamp}.log"
    local collectedOut="${collectedLogDir}/${computer}_${stamp}.out"

    if ! fetch_RemoteFile "$connection" "$remoteScriptLog" "$collectedLog";
    then
        log_Message "Unable to collect previous log from ${connection}" "ERROR"
        rm -f "$collectedLog"
        return 1
    fi
    if ! fetch_RemoteFile "$connection" "$remoteLogPath" "$collectedOut";
    then
        log_Message "Unable to collect previous nohup output from ${connection}" "WARN"
        rm -f "$collectedOut"
    fi

    add_SummaryRow "$computer" "$connection" "$collectedLog" "$collectedOut" "$scriptRunning"
    [[ -s "$collectedLog" ]] || rm -f "$collectedLog"
    [[ -s "$collectedOut" ]] || rm -f "$collectedOut"
    return 0
}

function main() {
	if [[ "$runMode" == '--logs-only' ]];
	then
		# Append so the log from the enrollment run is kept
		printf "Beginning ${scriptName} script (logs only)\n" >> "$logFile"
	else
		printf "Beginning ${scriptName} script\n" > "$logFile"
	fi

    check_Arguments

    mkdir -p "$collectedLogDir"
    if [[ ! -f "$summaryFile" ]];
    then
        printf 'Computer Name,Connection,Collected,Last Run,Outcome,MDM Identity,Detail,Script Output\n' > "$summaryFile"
    fi

    while IFS=, read -r -u 3 computerName ip 
    do
        computerName="${computerName%$'\r'}"
        ip="${ip%$'\r'}"
        [[ "$computerName" == *"Computer Name"* ]] && continue
        if ! check_Connection "$computerName";
        then
            log_Message "Unable to contact ${computerName} by hostname, trying by IP" "WARN"
            if ! check_Connection "$ip";
            then
                log_Message "Unable to contact ${computerName} at ${ip}, skipping" "ERROR"
                continue
            else
                computerConnection="$ip"
            fi
        else
            computerConnection="$computerName"
        fi

        "${scriptDir}/setup.expect" "$localAdmin" "$pass" "$computerConnection" "$sshKey" "$sshKeyPUBLIC"
        result="$?"
        case $result in
            0) ;;
            2)
                log_Message "Password rejected by ${computerConnection}, skipping" "ERROR"
                continue
                ;;
            3)
                log_Message "Timed out installing SSH key on ${computerConnection}, skipping" "ERROR"
                continue
                ;;
            *)
                log_Message "Failed to install SSH key on ${computerConnection}, skipping" "ERROR"
                continue
                ;;
        esac

        # Never start a second copy over one that is still waiting on the user
        remoteScript_Running "$computerConnection"
        result="$?"
        case $result in
            0)
                scriptRunning=false
                ;;
            10)
                scriptRunning=true
                ;;
            *)
                log_Message "Unable to check for a running enrollment script on ${computerConnection}, skipping" "ERROR"
                continue
                ;;
        esac

        # Grab the last runs logs before the new run overwrites them
        collect_RemoteLogs "$computerName" "$computerConnection" "$scriptRunning"

        if [[ "$runMode" == '--logs-only' ]];
        then
            continue
        fi

        if [[ "$scriptRunning" == true ]];
        then
            log_Message "Enrollment script still running on ${computerConnection}, skipping" "WARN"
            continue
        fi

        if { printf '%s\n' "$pass"; cat "${scriptDir}/remote_Fix_MDMEnrollment.sh"; } \
            | ssh -i "$sshKey" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o WarnWeakCrypto=no-pq-kex "${localAdmin}@${computerConnection}" \
                "sudo -S -p '' /bin/bash -c 'cat > ${remoteScriptPath} && chmod 700 ${remoteScriptPath} && { nohup ${remoteScriptPath} >${remoteLogPath} 2>&1 </dev/null & }'";
        then
            log_Message "Enrollment script successfully launched on ${computerConnection}"
        else
            log_Message "Failed to launch enrollment script on ${computerConnection}" "ERROR"
        fi

    done 3< "$csvFile"

    log_Message "Collected logs and summary saved to ${collectedLogDir}"
    exit 0
}

main
