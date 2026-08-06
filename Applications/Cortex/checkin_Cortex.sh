#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 07-13-26  ###
### Updated: 08-05-26  ###
### Version: 0.5       ###
##########################

pw="$4"
readonly jamfTrigger="$5"
readonly jamfFallbackTrigger="$6"
readonly jamfInstallVersion="$7"
readonly jamfFallbackVersion="$8"
readonly appName='Cortex XDR'
readonly appNameVersion="${appName} ${jamfInstallVersion}"
readonly appNameFallbackVersion="${appName} ${jamfFallbackVersion}"
readonly cortexApplicationPath='/Applications/Cortex XDR.app'
readonly cortexLibraryPath='/Library/Application Support/PaloAltoNetworks/Traps/bin'
readonly cytoolPath="${cortexLibraryPath}/cytool"
readonly installTimeout=180
readonly pollInterval=5
readonly logFile='/var/log/cortex_Checkin.log'
readonly logMaxSize=1048576
checkinState='none'
selfProtectDisabled='false'

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

# Create the log file, ensuring it hasnt outgrown logMaxSize
function log_Setup() {
    local logSize
    if [[ -f "$logFile" ]];
    then
        logSize="$(/usr/bin/stat -f%z "$logFile" 2>/dev/null)"
        if [[ -n "$logSize" ]] && ((logSize > logMaxSize));
        then
            : > "$logFile" 2>/dev/null
        fi
    fi
    touch "$logFile" 2>/dev/null
}

# Check for Cortex application
function app_Check(){
    [[ -d "$cortexApplicationPath" ]]
}

# Read the installed apps version
function get_Installed_Version() {
    defaults read "${cortexApplicationPath}/Contents/Info" CFBundleShortVersionString 2>/dev/null
}

# Compare two dotted version strings, returning 0 if $1 is at or above $2
function version_GTE() {
    [[ -n "$1" ]] || return 1
    [[ "$1" == "$2" ]] && return 0
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" ]]
}

# Compare the installed version against jamfInstallVersion
# 0 = at or above target, 1 = below target, 2 = undeterminable
function version_State() {
    local installedVersion="$1"

    if [[ -z "$installedVersion" ]];
    then
        return 2
    fi

    if version_GTE "$installedVersion" "$jamfInstallVersion";
    then
        return 0
    fi

    return 1
}

# Log and return the installed versions state against jamfInstallVersion
function version_Check() {
    local installedVersion state
    installedVersion="$(get_Installed_Version)"
    version_State "$installedVersion"
    state=$?

    case "$state" in
        0)
            if [[ "$installedVersion" == "$jamfInstallVersion" ]];
            then
                log_Message "Installed version (${installedVersion}) matches target (${jamfInstallVersion})"
            else
                log_Message "Installed version (${installedVersion}) is newer than target (${jamfInstallVersion}), leaving as is"
            fi
            ;;
        1)
            log_Message "Installed version (${installedVersion}) is older than target (${jamfInstallVersion})" "WARN"
            ;;
        *)
            log_Message "Unable to determine installed version" "ERROR"
            ;;
    esac

    return $state
}

# Check until the app is present and at or above the given version, or timeout
function wait_For_Version() {
    local target="$1"
    local elapsed=0

    while ((elapsed < installTimeout));
    do
        if app_Check && version_GTE "$(get_Installed_Version)" "$target";
        then
            return 0
        fi
        sleep "$pollInterval"
        ((elapsed += pollInterval))
    done

    return 1
}

# cytool check in attempt
function cytool_Checkin() {
    local output
    if [[ ! -f "$cytoolPath" ]];
    then
        log_Message "Unable to locate: \"${cytoolPath}\"" "ERROR"
        return 1
    fi

    if output="$("$cytoolPath" checkin 2>&1)";
    then
        log_Message "cytool check-in successful: ${output//$'\n'/ }"
        return 0
    else
        log_Message "Unable to check-in using cytool: ${output//$'\n'/ }" "WARN"
        return 1
    fi
}

# cytool reconnect attempt
function cytool_Reconnect() {
    local output
    if [[ ! -f "$cytoolPath" ]];
    then
        log_Message "Unable to locate: \"${cytoolPath}\"" "ERROR"
        return 1
    fi

    log_Message "Attempting cytool reconnect"
    if output="$("$cytoolPath" reconnect 2>&1)";
    then
        log_Message "cytool reconnect successful: ${output//$'\n'/ }"
        return 0
    else
        log_Message "Unable to reconnect using cytool: ${output//$'\n'/ }" "ERROR"
        return 1
    fi
}

# Disable SelfProt
function disable_Self_Protect() {
    local output
    if [[ ! -f "$cytoolPath" ]];
    then
        log_Message "Unable to locate: \"${cytoolPath}\"" "ERROR"
        return 1
    fi

    if output="$(echo "$pw" | sudo -S "$cytoolPath" security_modules disable self_prot 2>&1)";
    then
        selfProtectDisabled='true'
        log_Message "Successfully disabled SelfProt"
        return 0
    else
        log_Message "Unable to disable SelfProt: ${output//$'\n'/ }" "ERROR"
        return 1
    fi
}

# Re-enable SelfProt, but only if this script was the one that disabled it
function enable_Self_Protect() {
    local output
    [[ "$selfProtectDisabled" == 'true' ]] || return 0

    if [[ ! -f "$cytoolPath" ]];
    then
        log_Message "Unable to locate: \"${cytoolPath}\", SelfProt left disabled" "ERROR"
        return 1
    fi

    if output="$(echo "$pw" | sudo -S "$cytoolPath" security_modules enable self_prot 2>&1)";
    then
        selfProtectDisabled='false'
        log_Message "Successfully re-enabled SelfProt"
        return 0
    else
        log_Message "Unable to re-enable SelfProt, leaving it disabled: ${output//$'\n'/ }" "ERROR"
        return 1
    fi
}

# Run a jamf policy trigger, logging its output and exit status
function run_Policy() {
    local trigger="$1"
    local label="$2"
    local policyOutput policyStatus

    log_Message "Installing ${label}"
    policyOutput="$(/usr/local/bin/jamf policy -event "$trigger" 2>&1)"
    policyStatus=$?
    log_Message "jamf policy \"${trigger}\" exit ${policyStatus}: ${policyOutput//$'\n'/ }"
    return $policyStatus
}

# Run an install trigger and verify the result on disk
# Success is the target version being present, never the policy exit status
function install_Attempt() {
    local trigger="$1"
    local target="$2"
    local label="$3"
    local versionBefore versionAfter

    versionBefore="$(get_Installed_Version)"
    run_Policy "$trigger" "$label"

    if wait_For_Version "$target";
    then
        versionAfter="$(get_Installed_Version)"
        log_Message "Install verified: ${versionBefore:-none} -> ${versionAfter}"
        return 0
    fi

    versionAfter="$(get_Installed_Version)"
    if [[ "$versionBefore" == "$versionAfter" ]];
    then
        log_Message "Install left the version unchanged (${versionBefore:-none}) after ${installTimeout}s" "ERROR"
    else
        log_Message "Install left version ${versionAfter:-none}, still below target ${target}" "ERROR"
    fi

    return 1
}

# Install via jamf trigger or falling back to the fallback trigger
function install_App() {
    if install_Attempt "$jamfTrigger" "$jamfInstallVersion" "$appNameVersion";
    then
        return 0
    fi

    log_Message "Primary install did not reach ${jamfInstallVersion}, trying fallback" "WARN"
    if install_Attempt "$jamfFallbackTrigger" "$jamfFallbackVersion" "$appNameFallbackVersion";
    then
        log_Message "Running fallback version ${jamfFallbackVersion} instead of target ${jamfInstallVersion}" "WARN"
        return 0
    fi

    log_Message "Unable to install ${appName} using either trigger" "ERROR"
    return 1
}

# Set pw to random chars and then unset pw
function clean_Env() {
    if [[ -n "$pw" ]];
    then
        pw=$(head -c ${#pw} /dev/zero | tr '\0' 'X')
    fi
    unset pw
}

# Restore SelfProt, emit a single machine readable state line, then scrub pw
function cleanup() {
    local exitCode=$?
    local installedVersion

    enable_Self_Protect
    installedVersion="$(get_Installed_Version)"
    log_Message "RESULT: target=${jamfInstallVersion:-none} installed=${installedVersion:-none} checkin=${checkinState} exit=${exitCode}"
    clean_Env
}

function main() {
    local versionState

    trap "cleanup" EXIT INT TERM HUP

    log_Setup
    log_Message "Beginning ${appNameVersion} Check-in script"

    if [[ -z "$pw" ]] || [[ -z "$jamfTrigger" ]] || [[ -z "$jamfFallbackTrigger" ]] || [[ -z "$jamfInstallVersion" ]] || [[ -z "$jamfFallbackVersion" ]];
    then
        log_Message "Arguments not provided" "ERROR"
        [[ -n "$pw" ]] || log_Message "Missing PW"
        [[ -n "$jamfTrigger" ]] || log_Message "Missing Cortex Trigger"
        [[ -n "$jamfFallbackTrigger" ]] || log_Message "Missing Cortex Fallback Trigger"
        [[ -n "$jamfInstallVersion" ]] || log_Message "Missing Cortex Version"
        [[ -n "$jamfFallbackVersion" ]] || log_Message "Missing Cortex Fallback Version"
        exit 1
    fi

    # make sure the app is present and at or above the target version
    if ! app_Check;
    then
        log_Message "Unable to locate: ${cortexApplicationPath}"
        if ! install_App;
        then
            log_Message "${appName} failed to install" "ERROR"
            exit 1
        fi
        log_Message "${appName} installed successfully"
    else
        log_Message "Application present: ${cortexApplicationPath}"
    fi

    version_Check
    versionState=$?
    if ((versionState != 0));
    then
        log_Message "Installed version is not at target, attempting install" "WARN"
        if ! install_App;
        then
            log_Message "${appName} failed to update" "ERROR"
            exit 1
        fi
        log_Message "${appName} updated successfully"
    fi

    # app is present and current, confirm its checking in
    log_Message "Attempting to check in with ${appName}"
    if cytool_Checkin;
    then
        checkinState='ok'
        log_Message "${appNameVersion} check in finished"
        exit 0
    fi

    # checkin failed, try reconnect, then recheck
    if cytool_Reconnect && cytool_Checkin;
    then
        checkinState='ok-after-reconnect'
        log_Message "${appNameVersion} check-in finished after reconnect"
        exit 0
    fi

    # still not checking in, disable SelfProt and reinstall
    log_Message "Check-in still failing after reconnect, reinstalling ${appName}" "WARN"
    disable_Self_Protect

    if ! install_App;
    then
        log_Message "${appName} failed to reinstall" "ERROR"
        exit 1
    fi
    log_Message "${appName} reinstalled successfully"

    if ! version_Check;
    then
        log_Message "${appName} was reinstalled but is not at target version" "WARN"
    fi

    if cytool_Checkin;
    then
        checkinState='ok-after-reinstall'
        log_Message "${appNameVersion} check-in finished after reinstall"
        exit 0
    else
        checkinState='failed'
        log_Message "${appNameVersion} still not checking in after reinstall" "ERROR"
        exit 1
    fi
}

main
