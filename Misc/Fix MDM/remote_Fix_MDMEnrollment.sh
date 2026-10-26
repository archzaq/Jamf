#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 09-10-26   ###
###  Updated: 10-26-26   ###
###  Version: 1.4        ###
############################

readonly scriptName='remote_Fix_MDMEnrollment'
readonly logFile="/var/log/${scriptName}.log"
readonly SLUIconFile='/usr/local/jamfconnect/SLU.icns'
readonly genericIconFile='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
readonly dialogTitle='SLU ITS: Device Enrollment'
readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly enrollTimeout=300
readonly windowGrace=10
readonly removalTimeout=30
readonly maxAttempts=10000
attempt=0
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
            /usr/local/bin/jamf policy -event SLUFonts &>/dev/null
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
        set dialogResult to display dialog promptString buttons {"OK"} default button "OK" with icon POSIX file iconPath with title dialogTitle giving up after 900
        if gave up of dialogResult then
            return "TIMEOUT"
        end if
        return "OK"
    on error
        return "ERROR"
    end try
OOP
    )
    case "$dialogResult" in
        'OK')
            log_Message "Continued through dialog"
            return 0
            ;;
        'TIMEOUT')
            log_Message "Dialog timed out without a response" "WARN"
            return 2
            ;;
        *)
            log_Message "Unable to display dialog: ${dialogResult}" "ERROR"
            return 1
            ;;
    esac
}

# Check if the device currently has an MDM enrollment
function enrollment_Check() {
    /usr/bin/profiles status -type enrollment 2>/dev/null | grep -q 'MDM enrollment: Yes'
    return $?
}

# Check the MDM identity and Jamf built-in CA certificates in the System keychain
# Returns 0 if expired, 1 if still valid, 2 if no MDM identity was found
function mdmIdentity_Check() {
    local certs="$(/usr/bin/security find-certificate -a -p /Library/Keychains/System.keychain 2>/dev/null)"
    local line
    local pem=''
    local issuer
    local subject
    local expiry
    local status
    local identityExpiry=''
    local identityValid=false
    local caExpiry=''
    local caValid=false

    while IFS= read -r line;
    do
        pem+="$line"$'\n'
        if [[ "$line" != *"END CERTIFICATE"* ]];
        then
            continue
        fi
        issuer="$(/usr/bin/openssl x509 -noout -issuer <<< "$pem" 2>/dev/null)"
        if [[ "$issuer" == *"Built-in Certificate Authority"* ]];
        then
            subject="$(/usr/bin/openssl x509 -noout -subject <<< "$pem" 2>/dev/null)"
            expiry="$(/usr/bin/openssl x509 -noout -enddate <<< "$pem" 2>/dev/null | cut -d '=' -f 2)"
            status='valid'
            /usr/bin/openssl x509 -noout -checkend 0 <<< "$pem" &>/dev/null || status='EXPIRED'
            # The CA signs itself, anything else it issued is this Mac's MDM identity
            # Old certificates can be left behind, so one valid certificate of each kind is enough
            if [[ "${issuer#*=}" == "${subject#*=}" ]];
            then
                log_Message "Found Jamf CA certificate expiring ${expiry} (${status})"
                if [[ "$status" == 'valid' ]];
                then
                    caValid=true
                    caExpiry="$expiry"
                elif [[ "$caValid" == false ]];
                then
                    caExpiry="$expiry"
                fi
            else
                log_Message "Found MDM identity certificate expiring ${expiry} (${status})"
                if [[ "$status" == 'valid' ]];
                then
                    identityValid=true
                    identityExpiry="$expiry"
                elif [[ "$identityValid" == false ]];
                then
                    identityExpiry="$expiry"
                fi
            fi
        fi
        pem=''
    done <<< "$certs"

    if [[ -z "$identityExpiry" ]];
    then
        log_Message "No MDM identity certificate found" "ERROR"
        return 2
    fi
    if [[ "$identityValid" == false ]];
    then
        log_Message "MDM identity expired on ${identityExpiry}"
        return 0
    fi
    if [[ -n "$caExpiry" ]] && [[ "$caValid" == false ]];
    then
        log_Message "Jamf CA expired on ${caExpiry}"
        return 0
    fi
    log_Message "MDM identity valid until ${identityExpiry}"
    return 1
}

# Remove the Jamf framework along with the expired MDM profile, then wait for the profile to clear so the enrollment check only sees the new one
# The PreStage reinstalls the framework when the device re-enrolls
function remove_JamfFramework() {
    local removeOutput
    local lastLine
    local endTime
    if ! enrollment_Check;
    then
        log_Message "No existing MDM profile to remove"
        return 0
    fi
    if [[ ! -f '/usr/local/bin/jamf' ]];
    then
        log_Message "No Jamf binary found, unable to remove the Jamf framework" "ERROR"
        return 1
    fi

    log_Message "Removing the Jamf framework and existing MDM profile"
    removeOutput="$(/usr/local/bin/jamf removeFramework 2>&1)"
    endTime=$(($(date +%s) + removalTimeout))
    while [[ $(date +%s) -lt $endTime ]];
    do
        if ! enrollment_Check;
        then
            log_Message "MDM profile removed"
            return 0
        fi
        sleep 1
    done
    lastLine="$(printf '%s\n' "$removeOutput" | grep -v '^[[:space:]]*$' | tail -n 1)"
    log_Message "MDM profile still installed ${removalTimeout}s after removing the Jamf framework, it may not be removable${lastLine:+ (${lastLine})}" "ERROR"
    return 1
}

# Trigger the enrollment prompt inside the console user GUI session
function renew_Enrollment() {
    log_Message "Triggering enrollment prompt for $currentUser"
    /bin/launchctl asuser "$currentUserUID" /usr/bin/profiles renew -type enrollment &>/dev/null
    return $?
}

# Check if the Remote Management enrollment window (Setup Assistant) is open in the console user session
function enrollmentWindow_Check() {
    /usr/bin/pgrep -u "$currentUserUID" "Setup Assistant" &>/dev/null
    return $?
}

# Poll until the device reports an MDM enrollment, the enrollment window closes, or the timeout expires
function wait_ForEnrollment() {
    local endTime=$(($(date +%s) + enrollTimeout))
    local windowOpened=false
    local windowClosed=false

    # Wait for the window to appear, then keep checking until it goes away
    while [[ $(date +%s) -lt $endTime ]];
    do
        if enrollment_Check;
        then
            return 0
        fi
        if enrollmentWindow_Check;
        then
            if [[ "$windowOpened" == false ]];
            then
                windowOpened=true
                log_Message "Enrollment window opened"
            fi
        elif [[ "$windowOpened" == true ]];
        then
            windowClosed=true
            log_Message "Enrollment window closed"
            break
        fi
        sleep 1
    done

    if [[ "$windowClosed" == false ]];
    then
        if [[ "$windowOpened" == false ]];
        then
            log_Message "Enrollment window never appeared within ${enrollTimeout}s" "ERROR"
        else
            log_Message "Enrollment window still open after ${enrollTimeout}s" "ERROR"
        fi
        return 1
    fi

    # Enrollment can register just after the window closes, allow a short grace period before giving up
    endTime=$(($(date +%s) + windowGrace))
    while [[ $(date +%s) -lt $endTime ]];
    do
        if enrollment_Check;
        then
            return 0
        fi
        sleep 1
    done
    log_Message "Enrollment window closed without enrolling" "ERROR"
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

    # Only an expired MDM enrollment needs replacing, leave healthy Macs alone
    if enrollment_Check;
    then
        mdmIdentity_Check
        case $? in
            0)
                log_Message "Device reports an expired MDM enrollment, replacing it"
                ;;
            1)
                log_Message "Device already reports an MDM enrollment that is still valid"
                exit_Func
                ;;
            *)
                log_Message "Unable to confirm the MDM enrollment has expired, leaving it alone" "ERROR"
                exit_Func "error"
                ;;
        esac
    fi

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

    # Check this first for proper removal of permissions on exit
    if admin_Check "$currentUser";
    then
        existingAdmin=true
        log_Message "$currentUser is already an admin"
    fi

    ### START ###
    # Warn the user before anything pops up so the prompt is not dismissed
    while [[ $attempt -lt $maxAttempts ]];
    do
        display_Dialog "This Mac has lost its connection to SLU ITS device management and needs to be re-enrolled.\n\nIn a moment you will see a Device Enrollment notification from System Settings.\n\nYou MUST select \"Enroll\" for this to work.\n\nIf you miss the notification, open System Settings and look for the Device Enrollment prompt there."
        case $? in
            0)
                break
                ;;
            2)
                ((attempt++))
                ;;
            *)
                exit_Func "error"
                ;;
        esac
    done
    if [[ $attempt -ge $maxAttempts ]];
    then
        log_Message "$currentUser never responded to the dialog" "ERROR"
        exit_Func "error"
    fi

    precheckComplete=true

    # The expired profile blocks re-enrollment and would make the enrollment check report success, clear it first
    if ! remove_JamfFramework;
    then
        display_Dialog "Something went wrong preparing this Mac for enrollment.\n\nPlease contact the ITS Service Desk at (314)-977-4000."
        exit_Func "error"
    fi

    # Grant the permissions needed to approve the enrollment, watched the whole time
    if [[ "$existingAdmin" == false ]];
    then
        log_Message "Starting monitor" "SECURITY"
        monitor_Commands "$currentUser" "$((enrollTimeout + windowGrace))" &
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
        log_Message "Device did not enroll" "ERROR"
        display_Dialog "This Mac was not enrolled!\n\nPlease contact the ITS Service Desk at (314)-977-4000 so we may try again."
        exit_Func "error"
    fi
}

main
