#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 07-03-25  ###
### Updated: 07-04-25  ###
### Version: 1.2       ###
##########################

readonly defaultIconPath='/usr/local/jamfconnect/SLU.icns'
readonly genericIconPath='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
readonly dialogTitle='Management Fix'
readonly logPath='/var/log/management_Fix.log'
readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
existingAdmin=false

# Check if Jamf binary exists to determine which parameters to use
if [[ -f "/usr/local/jamf/bin/jamf" ]];
then
    readonly mAccountName="$4"
    readonly mAccountPass="$5"
    readonly tAccountName="$6"
    readonly tAccountPass="$7"
else
    readonly mAccountName="$1"
    readonly mAccountPass="$2"
    readonly tAccountName="$3"
    readonly tAccountPass="$4"
fi

# Append current status to log file
function log_Message() {
    local timestamp="$(date "+%F %T")"
    printf "Log: %s %s\n" "$timestamp" "$1" | tee -a "$logPath"
}

# Ensure external arguments are passed
function arg_Check() {
    if [[ -z "$mAccountName" ]] || [[ -z "$mAccountPass" ]] || [[ -z "$tAccountName" ]] || [[ -z "$tAccountPass" ]]; 
    then
        log_Message "ERROR: Missing critical arguments"
        exit 1
    fi
    readonly mAccountPath="/Users/${mAccountName}"
}

# Check for valid icon file, AppleScript dialog boxes will error without it
function icon_Check() {
    effectiveIconPath="$defaultIconPath"
    if [[ ! -f "$effectiveIconPath" ]];
    then
        log_Message "No SLU icon found"
        if [[ -f '/usr/local/bin/jamf' ]];
        then
            log_Message "Attempting icon install via Jamf"
            /usr/local/bin/jamf policy -event SLUFonts
        else
            log_Message "No Jamf binary found"
        fi
        if [[ ! -f "$effectiveIconPath" ]];
        then
            if [[ -f "$genericIconPath" ]];
            then
                log_Message "Generic icon found"
                effectiveIconPath="$genericIconPath"
            else
                log_Message "Generic icon not found"
                return 1
            fi
        fi
    else
        log_Message "SLU icon found"
    fi
    return 0
}

# Check if account exists
function account_Check() {
    local account="$1"
    /usr/bin/id "$account" &>/dev/null
    return $?
}

# Check if account is in the admin group
function admin_Check(){
    local account="$1"
    /usr/sbin/dseditgroup -o checkmember -m "$account" admin &>/dev/null
    return $?
}

# Check account for secure token
function token_Check() {
    local account="$1"
    /usr/sbin/sysadminctl -secureTokenStatus "$account" 2>&1 | grep -q 'ENABLED'
    return $?
}

# Creates account with a home folder and proper permissions
function create_Account() {
    local accountAdd="$1"
    local accountAddPass="$2"
    local accountAddPath="$3"
    local adminAccount="$4"
    local adminPassword="$5"
    if /usr/sbin/sysadminctl -addUser "$accountAdd" -password "$accountAddPass" -home "$accountAddPath" -admin -adminUser "$adminAccount" -adminPassword "$adminPassword" &>/dev/null;
    then
        log_Message "$accountAdd created"
        if account_Check "$accountAdd";
        then
            dirs=("Applications" "Desktop" "Documents" "Downloads" "Library" "Movies" "Music" "Pictures" "Public")
            for dir in "${dirs[@]}";
            do
                mkdir -p "$accountAddPath/$dir"
                chown "$accountAdd":staff "$accountAddPath/$dir"
                chmod 750 "$accountAddPath/$dir"
            done
            log_Message "$accountAdd successfully configured"
            return 0
        else
            log_Message "$accountAdd failed to be configured"
            return 1
        fi
    else
        log_Message "$accountAdd could not be created"
        return 1
    fi
}

# Add user to admin group
function addAccount_AdminGroup() {
    local account="$1"
    local adminAccount="$2"
    local adminPassword="$3"
    /usr/sbin/dseditgroup -o edit -a "$account" -u "$adminAccount" -P "$adminPassword" -t user -L admin &>/dev/null
    if admin_Check "$account";
    then
        log_Message "Permissions granted to $account"
        return 0
    else
        return 1
    fi
}

# Remove user from admin group
function removeAccount_AdminGroup() {
    local account="$1"
    local admin="$2"
    local adminPass="$3"
    if [ "$existingAdmin" != true ];
    then
        /usr/sbin/dseditgroup -o edit -d "$account" -u "$admin" -P "$adminPass" -t user -L admin &>/dev/null
        if ! admin_Check "$account";
        then
            log_Message "Permissions removed from $account"
            return 0
        else
            return 1
        fi
    else
        log_Message "Leaving $account permissions"
        return 0
    fi
}

# Change account password
function change_Pass() {
    local account="$1"
    local newPass="$2"
    local admin="$3"
    local adminPass="$4"
    /usr/sbin/sysadminctl -resetPasswordFor "$account" -newPassword "$newPass" -adminUser "$admin" -adminPassword "$adminPass" &>/dev/null
    return $?
}

# Verify password was changed properly
function verify_Pass() {
    local account="$1"
    local pass="$2"
    /usr/bin/dscl . -authonly "$account" "$pass" &>/dev/null
    return $?
}

# Update keychain with new password
function update_Keychain() {
    local account="$1"
    local oldPass="$2"
    local newPass="$3"
    local userHome=$(/usr/bin/dscl . -read "/Users/$account" NFSHomeDirectory | awk '{print $2}')
    local keychainPath="$userHome/Library/Keychains/login.keychain-db"
    if [[ -f "$keychainPath" ]];
    then
        if [[ -z "$oldPass" ]];
        then
            log_Message "Old password unknown, deleting keychain"
            local backupPath="$userHome/Library/Keychains/login.keychain-db.backup.$(date +%Y%m%d%H%M%S)"
            /bin/cp "$keychainPath" "$backupPath" 2>/dev/null
            if /bin/rm -f "$keychainPath";
            then
                log_Message "Successfully deleted keychain. New keychain will be created on next login"
            else
                log_Message "Failed to delete keychain"
                return 1
            fi
        else
            /usr/bin/security set-keychain-password -o "$oldPass" -p "$newPass" "$userHome/Library/Keychains/login.keychain-db" &>/dev/null
            if [[ $? -eq 0 ]];
            then
                log_Message "Login keychain password updated successfully"
            else
                log_Message "Could not update login keychain, user may need to update manually"
                /usr/bin/touch "$userHome/.keychain_update_required"
                /usr/sbin/chown "$account" "$userHome/.keychain_update_required"
                return 1
            fi
        fi
    else
        log_Message "Login keychain not found, skipping keychain update"
    fi

    return 0
}

# Clear password policy
function clear_PassPolicy() {
    local account="$1"
    /usr/bin/pwpolicy -u "$account" -clearaccountpolicies &>/dev/null
    return $?
}

# Change pass, verify pass, update keychain, and clear password policy
function reset_Password() {
    local account="$1"
    local newPass="$2"
    local admin="$3"
    local adminPass="$4"
    log_Message "Attempting to change password for $account"
    if ! change_Pass "$account" "$newPass" "$admin" "$adminPass";
    then
        log_Message "ERROR: Password change failed"
        return 1
    else
        log_Message "Password change completed successfully"
    fi

    log_Message "Verifying password change"
    if ! verify_Pass "$account" "$newPass";
    then
        log_Message "ERROR: Password change verification failed"
        return 1
    else
        log_Message "Password change verified successfully"
    fi

    log_Message "Updating account keychain"
    if ! update_Keychain "$account" "" "$newPass";
    then
        log_Message "ERROR: Keychain update failed"
    fi

    log_Message "Clearing password policy"
    if ! clear_PassPolicy "$account";
    then
        log_Message "ERROR: Clear password policy failed"
    else
        log_Message "Password policy cleared"
    fi

    return 0
}

# Assigns secure token to current user using $mAccountName
function assign_Token(){
    local adminAccount="$1"
    local adminPassword="$2"
    local tokenEnableAccount="$3"
    local tokenEnablePassword="$4"
    /usr/sbin/sysadminctl -adminUser "$adminAccount" -adminPassword "$adminPassword" -secureTokenOn "$tokenEnableAccount" -password "$tokenEnablePassword" &>/dev/null
    if token_Check "$tokenEnableAccount";
    then
        return 0
    else
        return 1
    fi
}

# AppleScript - Text field dialog prompt for inputting information
function textField_Dialog() {
    local promptString="$1"
    local dialogType="$2"
    local count=1
    while [ $count -le 10 ];
    do
        textFieldDialog=$(/usr/bin/osascript <<OOP
        try
            set promptString to "$promptString"
            set iconPath to "$effectiveIconPath"
            set dialogTitle to "$dialogTitle"
            set dialogType to "$dialogType"
            if dialogType is "hidden" then
                set dialogResult to display dialog promptString buttons {"Cancel", "OK"} default button "OK" with hidden answer default answer "" with icon POSIX file iconPath with title dialogTitle giving up after 900
            else
                set dialogResult to display dialog promptString buttons {"Cancel", "OK"} default button "OK" with answer default answer "" with icon POSIX file iconPath with title dialogTitle giving up after 900
            end if
            set buttonChoice to button returned of dialogResult
            if buttonChoice is equal to "OK" then
                return text returned of dialogResult
            else
                return "timeout"
            end if
        on error
            return "Cancel"
        end try
OOP
        )
        case "$textFieldDialog" in
            'Cancel')
                log_Message "User responded with: $textFieldDialog"
                return 1
                ;;
            'timeout')
                log_Message "No response, re-prompting ($count/10)"
                ((count++))
                ;;
            '')
                log_Message "Nothing entered in text field"
                alert_Dialog "Please enter something."
                ;;
            *)
                if [[ "$dialogType" == 'hidden' ]];
                then
                    log_Message "Password entered"
                else
                    log_Message "User responded with: $textFieldDialog"
                fi
                return 0
                ;;
        esac
    done
    return 1
}

# AppleScript - Create alert dialog window
function alert_Dialog() {
    local promptString="$1"
    log_Message "Displaying alert dialog."
    alertDialog=$(/usr/bin/osascript <<OOP
    try
        set promptString to "$promptString"
        set choice to (display alert promptString as critical buttons "OK" default button 1 giving up after 900)
        if (gave up of choice) is true then
            return "timeout"
        else
            return (button returned of choice)
        end if
    on error
        return "Error"
    end try
OOP
    )
    case "$alertDialog" in
        'Error')
            log_Message "Unable to show alert dialog"
            ;;
        'timeout')
            log_Message "Alert timed out"
            ;;
        *)
            log_Message "Continued through alert dialog"
            ;;
    esac
}

# Check to delete temporary account before exiting
function exit_Error() {
    if account_Check "$tAccountName";
    then
        /usr/sbin/sysadminctl -deleteUser "$tAccountName" -secure &>/dev/null
        log_Message "Temporary account deleted"
    fi
    exit 1
}

# Ensure $mAccountName is properly configured
function final_Check() {
    local account="$1"
    local exists=0
    local admin=0
    local token=0
    local pass=0
    if account_Check "$account";
    then
        exists=1
    fi
    if admin_Check "$account";
    then
        admin=1
    fi
    if token_Check "$account";
    then
        token=1
    fi
    if verify_Pass "$mAccountName" "$mAccountPass";
    then
        pass=1
    fi
    if [[ "$exists" == 1 ]] && [[ "$admin" == 1 ]] && [[ "$token" == 1 ]] && [[ "$pass" == 1 ]];
    then
        log_Message "Process completed successfully!"
        return 0
    fi

    return 1
}

function main() {
    ### PRECHECK ###
    printf "Log: $(date "+%F %T") Beginning Management Fix script\n" | tee "$logPath"
    arg_Check
    if ! account_Check "$tAccountName";
    then
        log_Message "ERROR: Missing temporary account"
        exit_Error
    fi

    if ! icon_Check;
    then
        log_Message "ERROR: Missing SLU icon"
        exit 1
    fi

    # Ensure $mAccountName exists
    log_Message "Checking for $mAccountName"
    if account_Check "$mAccountName";
    then
        log_Message "$mAccountName exists"
    else
        log_Message "$mAccountName does not exist"
        if ! create_Account "$mAccountName" "$mAccountPass" "$mAccountPath" "$tAccountName" "$tAccountPass";
        then
            log_Message "ERROR: Failed to create $mAccountName"
            exit_Error
        fi
    fi

    # Ensure $mAccountName is an admin
    log_Message "Checking permissions for $mAccountName"
    if admin_Check "$mAccountName";
    then
        log_Message "$mAccountName is an admin"
    else
        log_Message "$mAccountName is not an admin"
        if ! addAccount_AdminGroup "$mAccountName" "$tAccountName" "$tAccountPass";
        then
            log_Message "ERROR: Unable to grant admin rights"
            exit_Error
        else
            log_Message "$mAccountName is now an admin"
        fi
    fi

    # Ensure $currentUser has a secure token
    log_Message "Checking $currentUser for secure token"
    if ! token_Check "$currentUser";
    then
        log_Message "ERROR: $currentUser does not have a secure token"
        alert_Dialog "Your account does not have a Secure Token to grant to ${mAccountName}.\n\nRun SecureTokenManager policy to check Token status."
        exit_Error
    else
        log_Message "$currentUser has a secure token"
    fi

    # Prompt $currentUser for password
    log_Message "Prompting $currentUser for password"
    if ! textField_Dialog "Enter the password for $currentUser:" "hidden";
    then
        log_Message "Exiting at password prompt."
        if account_Check "$tAccountName";
        then
            /usr/sbin/sysadminctl -deleteUser "$tAccountName" -secure
            log_Message "Temporary account deleted"
        fi
        exit 0
    else
        currentUserPass="$textFieldDialog"
    fi

    # Check if $currentUser is already an admin
    log_Message "Checking permissions for $currentUser"
    if admin_Check "$currentUser";
    then
        log_Message "$currentUser already an admin"
        existingAdmin=true
    else
        if ! addAccount_AdminGroup "$currentUser" "$tAccountName" "$tAccountPass";
        then
            log_Message "ERROR: Unable to grant admin rights"
            currentUserPass=''
            exit_Error
        fi
    fi

    # Assign secure token to temporary account so that it can change $mAccountName password
    log_Message "Assigning secure token to temporary account"
    if ! assign_Token "$currentUser" "$currentUserPass" "$tAccountName" "$tAccountPass";
    then
        log_Message "ERROR: Unable to assign secure token to $tAccountName"
    else
        log_Message "Secure token assigned to $tAccountName"
        log_Message "Checking $mAccountName password"
        if ! verify_Pass "$mAccountName" "$mAccountPass";
        then
            log_Message "$mAccountName password is incorrect"
            if ! reset_Password "$mAccountName" "$mAccountPass" "$tAccountName" "$tAccountPass";
            then
                log_Message "ERROR: Exiting at password reset"
                exit_Error
            else
                log_Message "Successfully reset $mAccountName password"
            fi
        else
            log_Message "$mAccountName password is correct"
        fi
    fi
    
    # Ensure $mAccountName has secure token
    log_Message "Checking $mAccountName for secure token"
    if token_Check "$mAccountName";
    then
        log_Message "$mAccountName has a secure token"
    else
        log_Message "$mAccountName does not have a secure token"
        if ! assign_Token "$currentUser" "$currentUserPass" "$mAccountName" "$mAccountPass";
        then
            log_Message "ERROR: Unable to assign secure token to $mAccountName"
        else
            if token_Check "$mAccountName";
            then
                log_Message "Secure token assigned to $mAccountName"
            else
                log_Message "ERROR: Secure token not assigned"
            fi
        fi
    fi
    currentUserPass=''

    # Remove admin permission if necessary
    log_Message "Removing permissions"
    if ! removeAccount_AdminGroup "$currentUser" "$tAccountName" "$tAccountPass";
    then
        log_Message "ERROR: Unable to remove permissions"
    fi

    log_Message "Running final check"
    if final_Check "$mAccountName";
    then
        if account_Check "$tAccountName";
        then
            /usr/sbin/sysadminctl -deleteUser "$tAccountName" -secure
            log_Message "Temporary account deleted"
        fi
    else
        log_Message "$mAccountName still misconfigured"
        exit_Error
    fi

    log_Message "Exiting!"
    exit 0
}

main
