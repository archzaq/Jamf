#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 09-10-26   ###
###  Updated: 09-10-26   ###
###  Version: 1.0        ###
############################

readonly scriptName='remote_Fix_MDMEnrollment'
readonly logFile="/var/log/${scriptName}.log"
readonly SLUIconFile='/usr/local/jamfconnect/SLU.icns'
readonly genericIconFile='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
readonly dialogTitle='SLU ITS: Device Enrollment'
readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly enrollTimeout=600
activeIconPath="$SLUIconFile"
currentUserUID=''
existingAdmin=false
precheckComplete=false
trapExecuted=false
monitorPID=''

# Append current status to log file
function log_Message() {
    local message="$1"
    local logType="${2:-Log}"
    local timestamp="$(date "+%F %T")"
    printf "%s: %s %s\n" "$logType" "$timestamp" "$message" >> "$logFile"
}

# Check if someone is logged into the device
function check_Login() {
    if [[ "$currentUser" == 'loginwindow' ]] || [[ -z "$currentUser" ]] || [[ "$currentUser" == 'root' ]];
    then
        log_Message "No one currently logged in" "ERROR"
        return 1
    fi
    log_Message "$currentUser currently logged in"
    return 0
}

# Check for valid icon file, AppleScript dialog boxes will error without it
function icon_Check() {
    if [[ ! -f "$activeIconPath" ]];
    then
        log_Message "No SLU icon found"
        if [[ -f '/usr/local/bin/jamf' ]];
        then
            log_Message "Attempting icon install via Jamf"
            /usr/local/bin/jamf policy -event SLUFonts
        else
            log_Message "No Jamf binary found"
        fi
        if [[ ! -f "$activeIconPath" ]];
        then
            if [[ -f "$genericIconFile" ]];
            then
                log_Message "Generic icon found"
                activeIconPath="$genericIconFile"
            else
                log_Message "Generic icon not found" "ERROR"
                return 1
            fi
        fi
    else
        log_Message "SLU icon found"
    fi
    return 0
}

# Check if account is in the admin group
function admin_Check() {
    local account="$1"
    /usr/sbin/dseditgroup -o checkmember -m "$account" admin &>/dev/null
    return $?
}

# Add account to admin group
function addAccount_AdminGroup() {
    local account="$1"
    /usr/sbin/dseditgroup -o edit -a "$account" -t user admin &>/dev/null
    admin_Check "$account"
    return $?
}

# Remove account from admin group
function removeAccount_AdminGroup() {
    local account="$1"
    if [[ "$existingAdmin" == true ]];
    then
        log_Message "Leaving $account permissions, admin before this script ran"
        return 0
    fi
    /usr/sbin/dseditgroup -o edit -d "$account" -t user admin &>/dev/null
    if admin_Check "$account";
    then
        return 1
    fi
    return 0
}

# Monitor for sudo commands run by an account during vulnerable moments
function monitor_Commands() {
    local user="$1"
    local endTime=$(($(date +%s) + $2))
    while [[ $(date +%s) -lt $endTime ]];
    do
        for sudoPID in $(pgrep -u "root" "sudo" 2>/dev/null);
        do
            if ps -p "$sudoPID" -o ruser= | grep "$user" &>/dev/null;
            then
                log_Message "SUDO USED BY $user" "SECURITY"
                log_Message "Killing $sudoPID" "SECURITY"
                if kill -9 "$sudoPID" &>/dev/null;
                then
                    log_Message "Successfully killed $sudoPID" "SECURITY"
                else
                    log_Message "Unable to kill $sudoPID" "ERROR"
                fi
            fi
        done
        sleep 0.05
    done
}

# AppleScript - Single button dialog shown in the console user GUI session
function display_Dialog() {
    local promptString="${1//\"/\\\"}"
    local dialogResult
    log_Message "Displaying dialog to $currentUser"
    dialogResult=$(/bin/launchctl asuser "$currentUserUID" /usr/bin/sudo -u "$currentUser" /usr/bin/osascript 2>&1 <<OOP
    try
        set promptString to "$promptString"
        set iconPath to "$activeIconPath"
        set dialogTitle to "$dialogTitle"
        display dialog promptString buttons {"OK"} default button "OK" with icon POSIX file iconPath with title dialogTitle giving up after 900
        return "OK"
    on error
        return "ERROR"
    end try
OOP
    )
    if [[ "$dialogResult" != 'OK' ]];
    then
        log_Message "Unable to display dialog: ${dialogResult}" "ERROR"
        return 1
    fi
    log_Message "Continued through dialog"
    return 0
}

# Check if the device currently has an MDM enrollment
function enrollment_Check() {
    /usr/bin/profiles status -type enrollment 2>/dev/null | grep -q 'MDM enrollment: Yes'
    return $?
}

# Trigger the enrollment prompt inside the console user GUI session
function renew_Enrollment() {
    log_Message "Triggering enrollment prompt for $currentUser"
    /bin/launchctl asuser "$currentUserUID" /usr/bin/profiles renew -type enrollment &>/dev/null
    return $?
}

# Poll until the device reports an MDM enrollment or the window closes
function wait_ForEnrollment() {
    local endTime=$(($(date +%s) + enrollTimeout))
    while [[ $(date +%s) -lt $endTime ]];
    do
        if enrollment_Check;
        then
            return 0
        fi
        sleep 5
    done
    return 1
}

# Remove any granted permissions, ensure monitor is killed
function exit_Func() {
    local type="$1"
    if [[ "$trapExecuted" == true ]];
    then
        return
    fi
    trapExecuted=true

    if [[ "$precheckComplete" == true ]];
    then
        log_Message "Checking permissions for $currentUser"
        if ! removeAccount_AdminGroup "$currentUser";
        then
            log_Message "Unable to remove permissions from $currentUser" "ERROR"
        else
            log_Message "$currentUser permissions handled"
        fi

        if [[ -n "$monitorPID" ]];
        then
            if ps "$monitorPID" &>/dev/null;
            then
                log_Message "Killing monitor" "SECURITY"
                if kill "$monitorPID" &>/dev/null;
                then
                    log_Message "Monitor killed" "SECURITY"
                else
                    log_Message "Monitor not killed. Kill $monitorPID in Activity Monitor" "ERROR"
                fi
            else
                log_Message "Monitor PID not found, already exited" "SECURITY"
            fi
        fi
    fi

    if [[ "$type" == 'error' ]];
    then
        log_Message "Exiting" "ERROR"
        exit 1
    else
        log_Message "Exiting!"
        exit 0
    fi
}

function main() {
    ### PRECHECK ###
    trap "exit_Func" EXIT
    trap 'log_Message "Script interrupt" "ERROR"; exit_Func "error"' INT TERM
    printf "Log: $(date "+%F %T") Beginning ${scriptName} script\n" > "$logFile"

    # Ensure someone is at the GUI to answer the enrollment prompt
    if ! check_Login;
    then
        exit_Func "error"
    fi
    currentUserUID="$(/usr/bin/id -u "$currentUser")"

    # Check for icon files for AppleScript dialog
    if ! icon_Check;
    then
        log_Message "Missing SLU icon" "ERROR"
        exit_Func "error"
    fi

    # Nothing to do if the device is already enrolled
    if enrollment_Check;
    then
        log_Message "Device already reports an MDM enrollment"
        display_Dialog "This Mac is already enrolled.\n\nNo action is needed."
        exit_Func
    fi

    # Check this first for proper removal of permissions on exit
    if admin_Check "$currentUser";
    then
        existingAdmin=true
        log_Message "$currentUser is already an admin"
    fi

    ### START ###
    # Warn the user before anything pops up so the prompt is not dismissed
    display_Dialog "This Mac has lost its connection to SLU ITS device management and needs to be re-enrolled.\n\nIn a moment you will see a Device Enrollment notification from System Settings.\n\nYou MUST select \"Enroll\" for this to work. If you dismiss it, this Mac will stay unmanaged.\n\nIf you miss the notification, open System Settings and look for the Device Enrollment prompt there."

    precheckComplete=true

    # Grant the permissions needed to approve the enrollment, watched the whole time
    if [[ "$existingAdmin" == false ]];
    then
        log_Message "Starting monitor" "SECURITY"
        monitor_Commands "$currentUser" "$enrollTimeout" &
        monitorPID=$!
        log_Message "Granting temporary permissions to $currentUser"
        if ! addAccount_AdminGroup "$currentUser";
        then
            log_Message "Unable to grant permissions to $currentUser" "ERROR"
            display_Dialog "Something went wrong preparing this Mac for enrollment.\n\nPlease contact the ITS Service Desk at (314)-977-4000."
            exit_Func "error"
        fi
        log_Message "$currentUser is now an admin"
    fi

    # Pop the enrollment prompt in the user GUI session
    if ! renew_Enrollment;
    then
        log_Message "profiles renew returned an error" "ERROR"
    fi

    # Hold permissions open only until the enrollment lands
    log_Message "Waiting up to ${enrollTimeout}s for $currentUser to complete enrollment"
    if wait_ForEnrollment;
    then
        log_Message "Device successfully enrolled"
        display_Dialog "This Mac is now enrolled!\n\nThank you!"
        exit_Func
    else
        log_Message "Device did not enroll within ${enrollTimeout}s" "ERROR"
        display_Dialog "This Mac was not enrolled!\n\nPlease contact the ITS Service Desk at (314)-977-4000 so we may try again."
        exit_Func "error"
    fi
}

main
