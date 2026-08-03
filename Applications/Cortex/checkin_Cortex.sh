#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 07-13-26  ###
### Updated: 08-03-26  ###
### Version: 0.4       ###
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
readonly installWait=10
readonly logFile="/var/log/cortex_Checkin-${jamfInstallVersion}.log"

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

# Check for Cortex application
function app_Check(){
    [[ -d "$cortexApplicationPath" ]]
}

# Read the installed apps version
function get_Installed_Version() {
    defaults read "${cortexApplicationPath}/Contents/Info" CFBundleShortVersionString 2>/dev/null
}

# Compare installed version against jamfInstallVersion
function version_Check() {
    local installedVersion
    installedVersion="$(get_Installed_Version)"

    if [[ -z "$installedVersion" ]];
    then
        log_Message "Unable to determine installed version" "ERROR"
        return 1
    fi

    if [[ "$installedVersion" == "$jamfInstallVersion" ]];
    then
        log_Message "Installed version (${installedVersion}) matches target (${jamfInstallVersion})"
        return 0
    else
        log_Message "Installed version (${installedVersion}) does not match target (${jamfInstallVersion})" "WARN"
        return 1
    fi
}

# cytool check in attempt
function cytool_Checkin() {
    if [[ ! -f "$cytoolPath" ]];
    then
        log_Message "Unable to locate: \"${cytoolPath}\"" "ERROR"
        return 1
    fi

    if "$cytoolPath" checkin &>/dev/null;
    then
        log_Message "cytool check-in successful"
        return 0
    else
        log_Message "Unable to check-in using cytool" "WARN"
        return 1
    fi
}

# cytool reconnect attempt
function cytool_Reconnect() {
    if [[ ! -f "$cytoolPath" ]];
    then
        log_Message "Unable to locate: \"${cytoolPath}\"" "ERROR"
        return 1
    fi

    log_Message "Attempting cytool reconnect"
    if "$cytoolPath" reconnect &>/dev/null;
    then
        log_Message "cytool reconnect successful"
        return 0
    else
        log_Message "Unable to reconnect using cytool" "ERROR"
        return 1
    fi
}

# Disable SelfProt
function disable_Self_Protect() {
    if [[ ! -f "$cytoolPath" ]];
    then
        log_Message "Unable to locate: \"${cytoolPath}\"" "ERROR"
        return 1
    fi

    if echo "$pw" | sudo -S "$cytoolPath" security_modules disable self_prot &>/dev/null;
    then
        log_Message "Successfully disabled SelfProt"
        return 0
    else
        log_Message "Unable to disable SelfProt" "ERROR"
        return 1
    fi
}

# Install via jamf trigger or falling back to the fallback trigger
function install_App() {
    log_Message "Installing ${appNameVersion}"
    if /usr/local/bin/jamf policy -event "$jamfTrigger" &>/dev/null;
    then
        log_Message "Successfully ran install policy: ${appNameVersion}"
    else
        log_Message "Unable to run install policy: ${appNameVersion}" "ERROR"
    fi

    sleep "$installWait"

    if app_Check;
    then
        log_Message "Application present: ${cortexApplicationPath}"
        return 0
    fi

    log_Message "Unable to locate: ${cortexApplicationPath} after install attempt" "ERROR"
    log_Message "Installing ${appNameFallbackVersion}"
    if /usr/local/bin/jamf policy -event "$jamfFallbackTrigger" &>/dev/null;
    then
        log_Message "Successfully ran fallback install policy: ${appNameFallbackVersion}"
    else
        log_Message "Unable to run fallback install policy: ${appNameFallbackVersion}" "ERROR"
    fi

    sleep "$installWait"

    if app_Check;
    then
        log_Message "Application present: ${cortexApplicationPath}"
        return 0
    else
        log_Message "Unable to locate: ${cortexApplicationPath} after fallback install attempt" "ERROR"
        return 1
    fi
}

# Set pw to random chars and then unset pw
function clean_Env() {
    if [[ -n "$pw" ]];
    then
        pw=$(head -c ${#pw} /dev/zero | tr '\0' 'X')
    fi
    unset pw
}

function main() {
    trap "clean_Env" EXIT INT TERM HUP

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

    printf "Log: $(date "+%F %T") Beginning ${appNameVersion} Check-in script\n" | tee "$logFile"

    # make sure the app is present and on the target version
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

    if ! version_Check;
    then
        log_Message "Installed version does not match target, attempting reinstall" "WARN"
        if ! install_App;
        then
            log_Message "${appName} failed to update" "ERROR"
            exit 1
        fi
        log_Message "${appName} updated successfully"
    else
        log_Message "${appName} is the correct version: ${jamfInstallVersion}"
    fi

    # app is present, confirm its checking in
    log_Message "Attempting to check in with ${appName}"
    if cytool_Checkin;
    then
        log_Message "${appNameVersion} check in finished"
        exit 0
    fi

    # checkin failed, try reconnect, then recheck
    if cytool_Reconnect && cytool_Checkin;
    then
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

    if cytool_Checkin;
    then
        log_Message "${appNameVersion} check-in finished after reinstall"
        exit 0
    else
        log_Message "${appNameVersion} still not checking in after reinstall" "ERROR"
        exit 1
    fi
}

main
