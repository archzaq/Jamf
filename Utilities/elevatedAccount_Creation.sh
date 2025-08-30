#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 08-27-24  ###
### Updated: 08-30-25  ###
### Version: 2.3       ###
##########################

managementAccount="$4"
managementAccountPass="$5"
elevatedAccount="$6"
elevatedAccountPass=''
readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly logFile='/var/log/elevatedAccount_Creation.log'
readonly SLUIconFile='/usr/local/jamfconnect/SLU.icns'
readonly genericIconFile='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
readonly dialogTitle='SLU ITS: Elevated Account Creation'
readonly maxAttempts=10

# Append current status to log file
function log_Message() {
    local message="$1"
    local logType="${2:-Log}"
    local timestamp="$(date "+%F %T")"
    printf "%s: %s %s\n" "$logType" "$timestamp" "$message" | tee -a "$logFile"
}

# Ensure external arguments are passed
function arg_Check() {
    if [[ -z "$managementAccount" ]] || [[ -z "$managementAccountPass" ]] || [[ -z "$elevatedAccount" ]]; 
    then
        log_Message "Missing critical arguments" "ERROR"
        return 1
    fi
    return 0
}

# Check for valid icon file, AppleScript dialog boxes will error without it
function icon_Check() {
    activeIcon="$SLUIconFile"
    if [[ ! -f "$activeIcon" ]];
    then
        log_Message "No SLU icon found"
        if [[ -f '/usr/local/bin/jamf' ]];
        then
            log_Message "Attempting icon install via Jamf"
            /usr/local/bin/jamf policy -event SLUFonts
        else
            log_Message "No Jamf binary found"
        fi
        if [[ ! -f "$activeIcon" ]];
        then
            if [[ -f "$genericIconFile" ]];
            then
                log_Message "Generic icon found"
                activeIcon="$genericIconFile"
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

# Check if someone is logged into the device
function login_Check() {
    if [[ "$currentUser" == 'loginwindow' ]] || [[ -z "$currentUser" ]] || [[ "$currentUser" == 'root' ]];
    then
        log_Message "No one currently logged in" "ERROR"
        return 1
    else
        log_Message "Currently logged in: \"${currentUser}\""
        return 0
    fi
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

# Check account for Secure Token
function token_Check() {
    local account="$1"
    /usr/sbin/sysadminctl -secureTokenStatus "$account" 2>&1 | grep -q 'ENABLED'
    return $?
}

# Creates account with a home folder and proper permissions
function create_AdminAccount() {
    local accountAdd="$1"
    local accountAddPass="$2"
    local accountAddPath="$3"
    local adminAccount="$4"
    local adminPass="$5"
    if /usr/sbin/sysadminctl -addUser "$accountAdd" -password "$accountAddPass" -home "$accountAddPath" -admin -adminUser "$adminAccount" -adminPassword "$adminPass" &>/dev/null;
    then
        log_Message "Successfully created account: \"${accountAdd}\""
        if account_Check "$accountAdd";
        then
            dirs=("Applications" "Desktop" "Documents" "Downloads" "Movies" "Music" "Pictures" "Public")
            for dir in "${dirs[@]}";
            do
                mkdir -p "$accountAddPath/$dir"
                chown "$accountAdd":staff "$accountAddPath/$dir"
                chmod 750 "$accountAddPath/$dir"
            done
            chown -R "$accountAdd":staff "$accountAddPath"
            chmod +a "group:everyone deny delete" "$accountAddPath"
            chmod 750 "$accountAddPath"
            log_Message "Successfully configured: \"${accountAdd}\""
            return 0
        else
            log_Message "Failed to configure: \"${accountAdd}\"" "ERROR"
        fi
    else
        log_Message "Failed to create: \"${accountAdd}\"" "ERROR"
    fi
    return 1
}

# Assigns Secure Token to an account
function assign_Token(){
    local adminAccount="$1"
    local adminPass="$2"
    local tokenEnableAccount="$3"
    local tokenEnablePass="$4"
    local output
    output=$(/usr/sbin/sysadminctl -adminUser "$adminAccount" -adminPassword "$adminPass" -secureTokenOn "$tokenEnableAccount" -password "$tokenEnablePass" 2>&1)
    if token_Check "$tokenEnableAccount";
    then
        return 0
    else
        log_Message "Assign token failed, sysadminctl output: $output" "ERROR"
        return 1
    fi
}

# Ensure password complexity
function validate_Password() {
    local password="$1"
    local minLength=10
    if [[ ${#password} -lt $minLength ]];
    then
        alert_Dialog "Weak Password" "Password must be at least $minLength characters"
        return 1
    fi
    if ! [[ "$password" =~ [0-9] ]] || ! [[ "$password" =~ [A-Z] ]] || ! [[ "$password" =~ [a-z] ]];
    then
        alert_Dialog "Weak Password" "Password must contain uppercase, lowercase, and numbers"
        return 1
    fi
    return 0
}

# AppleScript - Informing the user and giving them two choices
function binary_Dialog() {
    local promptString="$1"
    local count=1
    while [ $count -le $maxAttempts ];
    do
        binDialog=$(/usr/bin/osascript <<OOP
        try
            set promptString to "$promptString"
            set iconPath to "$activeIcon"
            set dialogTitle to "$dialogTitle"
            set dialogResult to display dialog promptString buttons {"Cancel", "Yes"} default button "Yes" with icon POSIX file iconPath with title dialogTitle giving up after 900
            set buttonChoice to button returned of dialogResult
            if buttonChoice is equal to "" then
                return "TIMEOUT"
            else
                return buttonChoice
            end if
        on error
            return "CANCEL"
        end try
OOP
        )
        case "$binDialog" in
            'CANCEL' | 'Cancel')
                log_Message "User responded with: $binDialog"
                return 1
                ;;
            'TIMEOUT')
                log_Message "No response, re-prompting ($count/10)" "WARNING"
                ((count++))
                ;;
            *)
                log_Message "User responded with: $binDialog"
                return 0
                ;;
        esac
    done
    return 1
}

# AppleScript - Text field dialog prompt for inputting information
function textField_Dialog() {
    local promptString="$1"
    local dialogType="$2"
    local count=1
    while [ $count -le $maxAttempts ];
    do
        textFieldDialog=$(/usr/bin/osascript <<OOP
        try
            set promptString to "$promptString"
            set iconFile to "$activeIcon"
            set dialogTitle to "$dialogTitle"
            set dialogType to "$dialogType"
            if dialogType is "hidden" then
                set dialogResult to display dialog promptString buttons {"Cancel", "OK"} default button "OK" with hidden answer default answer "" with icon POSIX file iconFile with title dialogTitle giving up after 900
            else
                set dialogResult to display dialog promptString buttons {"Cancel", "OK"} default button "OK" with answer default answer "" with icon POSIX file iconFile with title dialogTitle giving up after 900
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
                log_Message "User responded with: \"${textFieldDialog}\""
                return 1
                ;;
            'timeout')
                log_Message "No response, re-prompting ($count/10)" "WARNING"
                ((count++))
                ;;
            '')
                log_Message "Nothing entered in text field"
                alert_Dialog "An Error Has Occurred" "Please enter something or select cancel"
                ;;
            *)
                if [[ "$dialogType" == 'hidden' ]];
                then
                    log_Message "Continued through prompt"
                else
                    log_Message "User responded with: \"${textFieldDialog}\""
                fi
                return 0
                ;;
        esac
    done
    return 1
}

# AppleScript - Create alert dialog window
function alert_Dialog() {
    local alertTitle="$1"
    local alertMessage="$2"
    log_Message "Displaying alert dialog"
    alertDialog=$(/usr/bin/osascript <<OOP
    try
        set alertTitle to "$alertTitle"
        set alertMessage to "$alertMessage"
        set choice to (display alert alertTitle message alertMessage as critical buttons "OK" default button 1 giving up after 900)
        if (gave up of choice) is true then
            return "TIMEOUT"
        else
            return (button returned of choice)
        end if
    on error
        return "ERROR"
    end try
OOP
    )
    case "$alertDialog" in
        'ERROR')
            log_Message "Unable to show alert dialog"
            ;;
        'TIMEOUT')
            log_Message "Alert timed out" "WARNING"
            ;;
        *)
            log_Message "Continued through alert dialog"
            ;;
    esac
}

function clean_Env() {
    elevatedAccountPass=''
    elevatedAccountPassVerify=''
    unset elevatedAccountPass
    unset elevatedAccountPassVerify
}

function clean_Exit() {
    clean_Env
    managementAccountPass=''
    unset managementAccountPass
}

function main() {
    trap "clean_Exit" EXIT INT TERM HUP
    printf "Log: $(date "+%F %T") Beginning Elevated Account Creation script\n" | tee "$logFile"

    if ! arg_Check;
    then
        log_Message "Exiting at argument check"
        exit 1
    fi

    log_Message "Checking for icon file"
    if ! icon_Check;
    then
        log_Message "Exiting at icon check"
        exit 1
    fi

    log_Message "Checking for currently logged in user"
    if ! login_Check;
    then
        log_Message "Exiting at login check"
        exit 1
    fi

    log_Message "Checking for: \"$managementAccount\""
    if ! account_Check "$managementAccount";
    then
        log_Message "Management account does not exist, exiting" "ERROR"
        alert_Dialog "Missing Account" "${managementAccount} account does not exist!"
        exit 1
    fi

    log_Message "Checking for: \"$elevatedAccount\""
    if account_Check "$elevatedAccount";
    then
        log_Message "Elevated account already exists" "ERROR"
        if ! binary_Dialog "Elevated account already exists!\n\nWould you like to delete this account and create a new one?";
        then
            log_Message "Exiting at binary dialog"
            exit 1
        else
            log_Message "Deleting elevate account"
            if sysadminctl -deleteUser "$elevatedAccount" -secure &>/dev/null;
            then
                log_Message "Elevated account deleted"
            else
                log_Message "Unable to delete elevate account" "ERROR"
                exit 1
            fi
        fi
    fi

    log_Message "Checking permissions for: \"$managementAccount\""
    if ! admin_Check "$managementAccount";
    then
        log_Message "Management account is not an admin, exiting" "ERROR"
        alert_Dialog "Insufficient Permissions" "${managementAccount} account is not an admin!"
        exit 1
    fi

    validPass=false
    while [[ "$validPass" == false ]];
    do
        log_Message "Prompting user for elevated account INFO"
        if ! textField_Dialog "Please enter the password you would like to use for your admin account:" "hidden";
        then
            log_Message "Exiting at INFO prompt"
            exit 0
        else
            elevatedAccountPass="${textFieldDialog}"
            textFieldDialog=''
            unset textFieldDialog
            if validate_Password "$elevatedAccountPass";
            then
                log_Message "INFO sufficiently complex"
                log_Message "Prompting user to verify INFO"
                if ! textField_Dialog "Verify the password by entering it again:" "hidden";
                then
                    log_Message "Exiting at INFO verification"
                    exit 0
                else
                    elevatedAccountPassVerify="${textFieldDialog}"
                    textFieldDialog=''
                    unset textFieldDialog
                fi

                if [[ "$elevatedAccountPass" == "$elevatedAccountPassVerify" ]];
                then
                    log_Message "INFO match, continuing"
                    elevatedAccountPassVerify=''
                    unset elevatedAccountPassVerify
                    validPass=true
                else
                    log_Message "INFO do not match" "ERROR"
                    alert_Dialog "Password Error" "Passwords do not match!"
                fi
            fi
        fi
    done

    log_Message "Creating account: \"${elevatedAccount}\""
    elevatedAccountPath="/Users/${elevatedAccount}"
    if ! create_AdminAccount "$elevatedAccount" "$elevatedAccountPass" "$elevatedAccountPath" "$managementAccount" "$managementAccountPass";
    then
        log_Message "Exiting at account creation"
        alert_Dialog "Account Creation Error" "Unable to complete account creation!"
        exit 1
    fi

    if ! token_Check "$elevatedAccount";
    then
        log_Message "Secure Token not assigned to: \"${elevatedAccount}\""
        if token_Check "$managementAccount";
        then
            log_Message "Secure Token present for: \"${managementAccount}\""
            if ! assign_Token "$managementAccount" "$managementAccountPass" "$elevatedAccount" "$elevatedAccountPass";
            then
                log_Message "Unable to assign Secure Token to: \"${elevatedAccount}\"" "ERROR"
            else
                log_Message "Secure Token successfully assigned to: \"${elevatedAccount}\""
            fi
        else
            log_Message "\"${managementAccount}\" does not have a Secure Token to assign to \"${elevatedAccount}\"" "ERROR"
        fi
    else
        log_Message "Secure Token already assigned to: \"${elevatedAccount}\""
    fi
    clean_Env
    
    /usr/bin/osascript -e 'display dialog "Process completed successfully!" buttons {"OK"} default button "OK" with icon POSIX file "'"$activeIcon"'" with title "'"$dialogTitle"'"' &>/dev/null
    log_Message "Elevated Account Creation finished! Exiting"
    exit 0
}

main

