#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 06-07-25  ###
### Updated: 07-08-25  ###
### Version: 1.5       ###
##########################

readonly logPath='/var/log/CyberArk_Update.log'
readonly admin="$4"
old="$5"
new="$6"

# Append current status to log file
function log_Message() {
    local timestamp="$(date "+%F %T")"
    printf "Log: %s %s\n" "$timestamp" "$1" | tee -a "$logPath"
}

# Check if account exists
function account_Check() {
    local account="$1"
    /usr/bin/id "$account" >/dev/null
    return $?
}

# Check account for secure token
function check_Token() {
    local account="$1"
    /usr/sbin/sysadminctl -secureTokenStatus "$account" 2>&1 | grep -q 'ENABLED'
    return $?
}

# Change account password
function change_Pass() {
    local account="$1"
    local newPass="$2"
    local adminAccount="$3"
    local oldPass="$4"
    local output
    output=$(/usr/sbin/sysadminctl -resetPasswordFor "$account" -newPassword "$newPass" -adminUser "$adminAccount" -adminPassword "$oldPass" 2>&1)
    if verify_PassChange "$account" "$newPass";
    then
        return 0
    else
        log_Message "ERROR: Change failed, sysadminctl output: $output"
        return 1
    fi
}

# Verify password was changed properly
function verify_PassChange() {
    local account="$1"
    local newPass="$2"
    /usr/bin/dscl . -authonly "$account" "$newPass" &>/dev/null
    return $?
}

# Update keychain with new password
function update_Keychain() {
    local account="$1"
    local oldPass="$2"
    local newPass="$3"
    local userHome=$(/usr/bin/dscl . -read "/Users/$account" NFSHomeDirectory | awk '{print $2}')
    if [[ -f "$userHome/Library/Keychains/login.keychain-db" ]];
    then
        /usr/bin/security set-keychain-password -o "$oldPass" -p "$newPass" "$userHome/Library/Keychains/login.keychain-db" 2>/dev/null
        if [[ $? -eq 0 ]];
        then
            log_Message "Login keychain password updated successfully"
            return 0
        else
            log_Message "Could not update login keychain, user may need to update manually"
            /usr/bin/touch "$userHome/.keychain_update_required"
            /usr/sbin/chown "$account" "$userHome/.keychain_update_required"
            return 1
        fi
    else
        log_Message "Login keychain not found, skipping keychain update"
        return 0
    fi
}

# Clear password policy
function clear_PassPolicy() {
    local account="$1"
    /usr/bin/pwpolicy -u "$account" -clearaccountpolicies 2>/dev/null
    return $?
}

# Ensure arguments are passed
function arg_Check() {
    if [ -z "$admin" ] || [ -z "$old" ] || [ -z "$new" ];
    then
        log_Message "ERROR: Missing critical arguments"
        exit 1
    fi
}

function trap_Clean() {
    old=''
    new=''
}

function main() {
    trap trap_Clean EXIT
    printf "Log: $(date "+%F %T") Beginning CyberArk PW Change script.\n" | tee "$logPath"

    arg_Check

    log_Message "Checking for $admin"
    if ! account_Check "$admin";
    then
        log_Message "$admin not found"
        exit 1
    fi
    log_Message "$admin found"

    log_Message "Checking for Secure Token"
    if check_Token "$admin";
    then
        log_Message "Secure Token currently Enabled for $admin"
        hasSecureToken=0
    else
        log_Message "Secure Token currently Disabled for $admin"
        hasSecureToken=1
    fi

    log_Message "Checking for current $admin password"
    if ! verify_PassChange "$admin" "$old";
    then
        log_Message "ERROR: Old password not properly set"
        log_Message "Run the following policy to resolve password issues: /usr/local/bin/jamf policy -event managementFix"
        exit 1
    else
        log_Message "Old password properly set"
    fi

    log_Message "Attempting to change password for $admin"
    if ! change_Pass "$admin" "$new" "$admin" "$old";
    then
        log_Message "ERROR: Password change command failed"
        exit 1
    else
        log_Message "Password change command completed"
    fi

    log_Message "Updating account keychain"
    if ! update_Keychain "$admin" "$old" "$new";
    then
        log_Message "ERROR: Keychain update failed"
    else
        log_Message "Account keychain updated"
    fi

    log_Message "Clearing password policy"
    if ! clear_PassPolicy "$admin";
    then
        log_Message "ERROR: Clear password policy failed"
    else
        log_Message "Password policy cleared"
    fi

    if [[ "$hasSecureToken" -eq 0 ]];
    then
        if check_Token "$admin";
        then
            log_Message "Secure token preserved after password change"
        else
            log_Message "Secure token lost during password change"
        fi
    fi
    
    log_Message "CyberArk password change completed successfully!"
    exit 0
}

main
