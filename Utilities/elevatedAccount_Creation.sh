#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 08-27-24  ###
### Updated: 08-11-25  ###
### Version: 2.0       ###
##########################

elevatedAccountPass=""
readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly logFile='/var/log/elevatedAccount_Creation.log'
readonly SLUIconFile='/usr/local/jamfconnect/SLU.icns'
readonly genericIconFile='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
readonly dialogTitle='SLU ITS: Elevated Account Creation'

# Append current status to log file
function log_Message() {
    local timestamp="$(date "+%F %T")"
    printf "Log: %s %s\n" "$timestamp" "$1" | tee -a "$logFile"
}

# Ensure external arguments are passed
function arg_Check() {
    if [[ -z "$managementAccount" ]] || [[ -z "$managementAccountPass" ]] || [[ -z "$elevatedAccount" ]]; 
    then
        log_Message "ERROR: Missing critical arguments"
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
                log_Message "ERROR: Generic icon not found"
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
        log_Message "No one currently logged in"
        return 1
    else
        log_Message "${currentUser} currently logged in"
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
        log_Message "$accountAdd created"
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
            chmod 750 "$accountAddPath"
            log_Message "$accountAdd successfully configured"
            return 0
        else
            log_Message "$accountAdd failed to be configured"
        fi
    else
        log_Message "$accountAdd could not be created"
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
        log_Message "ERROR: Change failed, sysadminctl output: $output"
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

# Secure credential handling - zero out memory after use
function secure_Cleanup() {
    # Overwrite variables multiple times before unsetting
    for var in managementAccountPass elevatedAccountPass elevatedAccountPassTest; do
        eval "$var=$(openssl rand -base64 32)"
        eval "$var=''"
        unset $var
    done
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
                log_Message "User responded with: $textFieldDialog"
                return 1
                ;;
            'timeout')
                log_Message "No response, re-prompting ($count/10)"
                ((count++))
                ;;
            '')
                log_Message "Nothing entered in text field"
                alert_Dialog "An Error Has Occurred" "Please enter something or select cancel."
                ;;
            *)
                if [[ "$dialogType" == 'hidden' ]];
                then
                    log_Message "Continued"
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
            log_Message "Alert timed out"
            ;;
        *)
            log_Message "Continued through alert dialog"
            ;;
    esac
}

function cleanup_Env() {
    managementAccountPass=''
    elevatedAccountPass=''
    elevatedAccountPassTest=''
    unset managementAccountPass
    unset elevatedAccountPass
    unset elevatedAccountPassTest
}

function main() {
    trap "cleanup_Env" EXIT INT TERM
    printf "Log: $(date "+%F %T") Beginning Elevated Account Creation script\n" | tee "$logFile"

    if ! arg_Check;
    then
        log_Message "Exiting at argument check"
        exit 1
    fi

    log_Message "Checking for SLU icon"
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
        log_Message "ERROR: Management account does not exist, exiting"
        alert_Dialog "Missing Account" "${managementAccount} account does not exist!"
        exit 1
    fi

    log_Message "Checking for: \"$elevatedAccount\""
    if account_Check "$elevatedAccount";
    then
        log_Message "ERROR: Elevated account already exists, exiting"
        alert_Dialog "Duplicate Account" "${elevatedAccount} account already exists!"
        exit 1
    fi

    log_Message "Checking admin rights for: \"$managementAccount\""
    if ! admin_Check "$managementAccount";
    then
        log_Message "ERROR: Management account is not an admin, exiting"
        alert_Dialog "Insufficient Permissions" "${managementAccount} account is not an admin!"
        exit 1
    fi

    validPass=false
    while [[ "$validPass" == false ]];
    do
        log_Message "Prompting user for elevated account pass"
        if ! textField_Dialog "Please enter the password you would like to use for your admin account:" "hidden";
        then
            log_Message "Exiting at password prompt"
            exit 0
        else
            elevatedAccountPass="${textFieldDialog}"
            textFieldDialog=''
            unset textFieldDialog
            if validate_Password "$elevatedAccountPass";
            then
                log_Message "Password sufficiently complex"
                if ! textField_Dialog "Verify the password by entering it again:" "hidden";
                then
                    log_Message "Exiting at password verification"
                    exit 0
                else
                    elevatedAccountPassTest="${textFieldDialog}"
                    textFieldDialog=''
                    unset textFieldDialog
                fi

                if [[ "$elevatedAccountPass" == "$elevatedAccountPassTest" ]];
                then
                    log_Message "Passwords match"
                    elevatedAccountPassTest=''
                    unset elevatedAccountPassTest
                    validPass=true
                else
                    log_Message "ERROR: Passwords do not match"
                    alert_Dialog "Password Error" "Passwords do not match!"
                fi
            fi
        fi
    done

    log_Message "Creating elevated account"
    elevatedAccountPath="/Users/${elevatedAccount}"
    if ! create_AdminAccount "$elevatedAccount" "$elevatedAccountPass" "$elevatedAccountPath" "$managementAccount" "$managementAccountPass";
    then
        log_Message "Exiting at account creation"
        alert_Dialog "Account Creation Error" "Unable to complete account creation!"
        exit 1
    fi

    if ! token_Check "$elevatedAccount";
    then
        log_Message "Secure Token not assigned"
        if token_Check "$managementAccount";
        then
            log_Message "${managementAccount} has Secure Token"
            if ! assign_Token "$managementAccount" "$managementAccountPass" "$elevatedAccount" "$elevatedAccountPass";
            then
                log_Message "ERROR: Unable to assign Secure Token to ${elevatedAccount}"
            else
                log_Message "Secure Token successfully assigned!"
            fi
        fi
    fi
    elevatedAccountPass=''
    managementAccountPass=''
    unset elevatedAccountPass
    unset managementAccountPass
    
    log_Message "Elevated account creation finished! Exiting"
    exit 0
}

if [[ -f "/usr/local/jamf/bin/jamf" ]];
then
    managementAccount="$4"
    managementAccountPass="$5"
    elevatedAccount="$6"
else
    managementAccount="$1"
    managementAccountPass="$2"
    elevatedAccount="$3"
fi

main

