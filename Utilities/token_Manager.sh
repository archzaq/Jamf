#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 03-12-25  ###
### Updated: 08-30-25  ###
### Version: 1.7       ###
##########################

readonly SLUIconFile='/usr/local/jamfconnect/SLU.icns'
readonly genericIconFile='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
readonly dialogTitle='Token Manager'
readonly logFile='/var/log/token_Manager.log'
readonly maxAttempts=10
readonly tAccountName="$4"
tAccountPass="$5"
activeIcon="$SLUIconFile"
monitorPID=''

# Check the script is ran with admin privileges
function sudo_Check() {
    if [ "$(id -u)" -ne 0 ];
    then
        log_Message "Please run this script as root or using sudo!" "ERROR"
        alert_Dialog "Please run this script as root or using sudo!"
        return 1
    fi
    return 0
}

# Append current status to log file
function log_Message() {
    local message="$1"
    local logType="${2:-Log}"
    local timestamp="$(date "+%F %T")"
    printf "%s: %s %s\n" "$logType" "$timestamp" "$message" | tee -a "$logFile"
}

# Check if account is in the admin group
function admin_Check(){
    local account="$1"
    /usr/sbin/dseditgroup -o checkmember -m "$account" admin &>/dev/null
    return $?
}

# Check if account exists
function account_Check() {
    local account="$1"
    /usr/bin/id "$account" &>/dev/null
    return $?
}

# Verify account password
function verify_Pass() {
    local account="$1"
    local pass="$2"
    /usr/bin/dscl . -authonly "$account" "$pass" &>/dev/null
    return $?
}

# Add account to admin group
function addAccount_AdminGroup() {
    local account="$1"
    local adminAccount="$2"
    local adminPass="$3"
    /usr/sbin/dseditgroup -o edit -a "$account" -u "$adminAccount" -P "$adminPass" -t user -L admin &>/dev/null
    sleep 1
    if admin_Check "$account";
    then
        return 0
    else
        return 1
    fi
}

# Remove account from admin group
function removeAccount_AdminGroup() {
    local account="$1"
    local adminAccount="$2"
    local adminPass="$3"
    if [ "$existingAdmin" -eq 0 ];
    then
        /usr/sbin/dseditgroup -o edit -d "$account" -u "$adminAccount" -P "$adminPass" -t user -L admin &>/dev/null
        if admin_Check "$account";
        then
            return 1
        fi
    else
        log_Message "Leaving $account permissions"
    fi
    return 0
}

# Check for valid icon file, AppleScript dialog boxes will error without it
function icon_Check() {
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

# Format different groups of secure token users for display in AppleScript
function create_TokenPhrase() {
    local message="$1"
    local arrayName="$2"
    local craftArrayName="${arrayName}[@]"
    local arrayCopy=("${!craftArrayName}")
    local userList

    log_Message "$message"
    if [[ ${#arrayCopy[@]} -eq 0 ]];
    then
        tokenPhrase=$(printf "%s\nNone" "$message")
        log_Message "None"
    else
        userList=$(printf "%s\n" "${arrayCopy[@]}")
        tokenPhrase=$(printf "%s\n%s" "$message" "$userList")
        for user in "${arrayCopy[@]}";
        do
            log_Message " - $user"
        done
    fi
}

# Grabs lists of each users current Secure Token and Admin status
function get_UserArrays() {
    secureTokenUserArray=()
    nonSecureTokenUserArray=()
    adminAccountArray=()
    secureTokenAdminArray=()
    log_Message "Getting secure token UIDs"
    local secureTokenUIDs=($(/usr/sbin/diskutil apfs listUsers / | grep -E '.*-.*' | awk '{print $2}'))
    for username in $(/usr/bin/dscl . -list /Users | grep -v "^_");
    do
        if [[ "$username" == 'daemon' || "$username" == 'nobody' || "$username" == 'root' || "$username" == 'temp_management' ]];
        then
            continue
        fi
        local admin=0
        local secureToken=0
        if admin_Check "$username";
        then
            admin=1
        fi
        local uuid=$(/usr/bin/dscl . -read /Users/"$username" GeneratedUID 2>/dev/null | awk '{print $2}')
        for tokenUID in "${secureTokenUIDs[@]}";
        do
            if [[ "$uuid" == "$tokenUID" ]];
            then
                secureToken=1
                break
            fi
        done
        if [ $admin -eq 1 ] && [ $secureToken -eq 1 ];
        then
            secureTokenUserArray+=("$username")
            adminAccountArray+=("$username")
            secureTokenAdminArray+=("$username")
        elif [ $admin -eq 1 ] && [ $secureToken -eq 0 ];
        then
            nonSecureTokenUserArray+=("$username")
            adminAccountArray+=("$username")
        elif [ $admin -eq 0 ] && [ $secureToken -eq 1 ];
        then
            secureTokenUserArray+=("$username")
        elif [ $admin -eq 0 ] && [ $secureToken -eq 0 ];
        then
            nonSecureTokenUserArray+=("$username")
        fi
    done

    create_TokenPhrase "Secure Token accounts:" "secureTokenUserArray"
    secureTokenPhrase="$tokenPhrase"

    create_TokenPhrase "Non-Secure Token accounts:" "nonSecureTokenUserArray"
    nonSecureTokenPhrase="$tokenPhrase"
    
    create_TokenPhrase "Admin accounts:" "adminAccountArray"
    adminAccountPhrase="$tokenPhrase"

    create_TokenPhrase "Admin accounts with Secure Tokens:" "secureTokenAdminArray"
    secureTokenAdminPhrase="$tokenPhrase"
}

# Function for adding and removing Secure Tokens
function token_Action() {
    local tokenAccount="$1"
    local tokenPassword="$2"
    local adminAccount="$3"
    local adminPassword="$4"
    local tokenAction="$5"
    local result
    if [[ "$tokenAction" == 'Add Token' ]];
    then
        result=$(su "$adminAccount" -c "/usr/sbin/sysadminctl -secureTokenOn \"$tokenAccount\" -password \"$tokenPassword\" -adminUser \"$adminAccount\" -adminPassword \"$adminPassword\"" 2>&1)
    elif [[ "$tokenAction" == 'Remove Token' ]];
    then
        result=$(su "$adminAccount" -c "/usr/sbin/sysadminctl -secureTokenOff \"$tokenAccount\" -password \"$tokenPassword\" -adminUser \"$adminAccount\" -adminPassword \"$adminPassword\"" 2>&1)
    else
        log_Message "Invalid token action" "ERROR"
        return 1
    fi
    if [[ "$result" == *"Done"* ]];
    then
        return 0
    else
        log_Message "sysadminctl result: ${result}" "ERROR"
        return 1
    fi
}

function INPROG_token_Action() {
    #readonly helperPath=''
    local tokenAccount="$1"
    local tokenPassword="$2"
    local adminAccount="$3"
    local adminPassword="$4"
    local tokenAction="$5"
    local operation
    local result
    if [[ "$tokenAction" == 'Add Token' ]];
    then
        operation='add'
    elif [[ "$tokenAction" == 'Remove Token' ]];
    then
        operation='remove'
    else
        log_Message "Invalid token action" "ERROR"
        return 1
    fi
    if [[ -f "$helperPath" ]];
    then
        result=$(printf "%s\n%s" "$tokenPassword" "$adminPassword" | \
            "$helperPath" "$operation" "$tokenAccount" "$adminAccount" 2>&1)
    else
        log_Message "No security tool found" "ERROR"
        return 1
    fi
    if [[ "$result" == "SUCCESS" ]];
    then
        return 0
    else
        log_Message "sysadminctl result: ${result}" "ERROR"
        return 1
    fi
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

# Main logic of Secure Token action being taken
function token_Action_Display() {
    local firstPrompt="$1"
    local secondPrompt="$2"
    local tokenActionType="$3"
    existingAdmin=1
    if ! textField_Dialog "$firstPrompt"
    then
        log_Message "Exiting at first \"${tokenActionType}\" text field dialog"
        return 1
    fi
    log_Message "Continued through \"${tokenActionType}\" text field dialog"
    adminAccount="$textFieldDialog"

    if ! account_Check "$adminAccount";
    then
        log_Message "$adminAccount does not exist" "ERROR"
        alert_Dialog "$adminAccount does not exist!"
        return 1
    fi

    if ! admin_Check "$adminAccount";
    then
        log_Message "$adminAccount is not an admin" "WARNING"
        existingAdmin=0
    else
        log_Message "$adminAccount is an admin"
        existingAdmin=1
    fi

    if ! textField_Dialog "$secondPrompt";
    then
        log_Message "Exiting at second $tokenActionType text field dialog"
        return 1
    fi
    log_Message "Continued through second $tokenActionType text field dialog"

    tokenAccount="$textFieldDialog"
    if ! account_Check "$tokenAccount";
    then
        log_Message "$tokenAccount does not exist" "ERROR"
        alert_Dialog "$tokenAccount does not exist!"
        return 1
    fi

    log_Message "Prompting for $adminAccount password"
    if ! textField_Dialog "Enter the password for $adminAccount:" "hidden";
    then
        log_Message "Exiting at first password prompt"
        return 1
    fi
    adminPassword="$textFieldDialog"

    if ! verify_Pass "$adminAccount" "$adminPassword";
    then
        log_Message "Incorrect password"
        alert_Dialog "Incorrect password!\n\nPlease try again"
        return 1
    fi

    log_Message "Prompting for $tokenAccount password"
    if ! textField_Dialog "Enter the password for $tokenAccount:" "hidden";
    then
        log_Message "Exiting at second password prompt"
        return 1
    fi
    tokenPassword="$textFieldDialog"

    if ! verify_Pass "$tokenAccount" "$tokenPassword";
    then
        log_Message "Incorrect password"
        alert_Dialog "Incorrect password!\n\nPlease try again"
        return 1
    fi

    if [ $existingAdmin -eq 0 ];
    then
        log_Message "Starting monitor" "SECURITY"
        monitor_Commands "$adminAccount" "30" &
        monitorPID=$!
        if ! admin_Check "$adminAccount";
        then
            if ! addAccount_AdminGroup "$adminAccount" "$tAccountName" "$tAccountPass";
            then
                log_Message "Unable to grant permissions to $adminAccount" "ERROR"
                alert_Dialog "Unable to proceed as $adminAccount has insufficient permissions"
                return 1
            fi
        else
            log_Message "$adminAccount is already an admin" "ERROR"
        fi
    fi

    if ! token_Action "$tokenAccount" "$tokenPassword" "$adminAccount" "$adminPassword" "$tokenActionType";
    then
        clean_Env
        log_Message "$(printf "Error with Secure token action!\nPriviliged Account: %s\nNon-Priviliged Account: %s\nToken Action: %s" "$adminAccount" "$tokenAccount" "$tokenActionType")" "ERROR"
        alert_Dialog "Error with Secure token action!\n\nPriviliged Account:\n${adminAccount}\n\nNon-Priviliged Account:\n${tokenAccount}\n\nToken Action:\n${tokenActionType}"
        return 1
    else
        clean_Env
        log_Message "$tokenActionType completed!"
        log_Message "Displaying Token Status dialog"
        get_UserArrays
        secureTokenCombinedPhrase="${secureTokenPhrase}\n\n${nonSecureTokenPhrase}"
        if binary_Dialog "Process completed successfully!\n\n${secureTokenCombinedPhrase}";
        then
            log_Message "Exiting at Token Status dialog"
            return 0
        fi
    fi
    return 1
}

# AppleScript - Create alert dialog window
function alert_Dialog() {
    local promptString="$1"
    log_Message "Displaying alert dialog"
    alertDialog=$(/usr/bin/osascript <<OOP
    try
        set promptString to "$promptString"
        set choice to (display alert promptString as critical buttons "OK" default button 1 giving up after 900)
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

# AppleScript - Ask user to choose from a list of items
function dropdown_Prompt() {
    local promptString="$1"
    local count=1
    while [ $count -le $maxAttempts ];
    do
        dropdownPrompt=$(/usr/bin/osascript <<OOP
        set promptString to "$promptString"
        set dialogTitle to "$dialogTitle"
        set dropdownOptions to {"Current Token Status", "Add Token", "Remove Token"}
        set userChoice to (choose from list dropdownOptions with prompt promptString cancel button name "Quit" default items "Current Token Status" with title dialogTitle)
        if userChoice is false then
            return "QUIT"
        else if userChoice is {} then
            return "TIMEOUT"
        else
            return (item 1 of userChoice)
        end if
OOP
        )
        case "$dropdownPrompt" in
            'QUIT')
                log_Message "User chose: \"Quit\""
                return 1
                ;;
            'TIMEOUT')
                log_Message "Timed out, re-prompting ($count/10)"
                ((count++))
                ;;
            *)
                log_Message "User chose: \"${dropdownPrompt}\""
                return 0
                ;;
        esac
    done
    return 1
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
            set dialogResult to display dialog promptString buttons {"Go Back", "Done"} default button "Done" with icon POSIX file iconPath with title dialogTitle giving up after 900
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
            'CANCEL' | 'Go Back')
                log_Message "User responded with: $binDialog"
                return 1
                ;;
            'TIMEOUT')
                log_Message "No response, re-prompting ($count/10)"
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
            set iconPath to "$activeIcon"
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
                return "TIMEOUT"
            end if
        on error
            return "CANCEL"
        end try
OOP
        )
        case "$textFieldDialog" in
            'CANCEL')
                log_Message "User responded with: \"${textFieldDialog}\""
                return 1
                ;;
            'TIMEOUT')
                log_Message "No response, re-prompting ($count/10)"
                ((count++))
                ;;
            '')
                log_Message "Nothing entered in text field" "ERROR"
                alert_Dialog "Please enter something"
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

# Ensure temporary account is removed
function delete_TempAccount() {
    if account_Check "$tAccountName";
    then
        log_Message "Deleting $tAccountName"
        if ! /usr/sbin/sysadminctl -deleteUser "$tAccountName" -secure &>/dev/null;
        then
            log_Message "$tAccountName not deleted" "ERROR"
        else
            log_Message "$tAccountName deleted"
        fi
    fi
}

function clean_Env() {
    if [[ -n "$adminAccount" ]] && [[ -n "$existingAdmin" ]] && [ $existingAdmin -eq 0 ];
    then
        if admin_Check "$adminAccount";
        then
            if ! removeAccount_AdminGroup "$adminAccount" "$tAccountName" "$tAccountPass";
            then
                log_Message "Unable to remove ${adminAccount} from admin group" "ERROR"
            else
                log_Message "${adminAccount} removed from admin group"
            fi
        else
            log_Message "${adminAccount} is not in admin group, leaving"
        fi
    else
        log_Message "Leaving permissions alone"
    fi

    local vars=("adminPassword" "tokenPassword")
    local varName
    for varName in "${vars[@]}";
    do
        if [[ -n "${!varName}" ]];
        then
            local varValue="${!varName}"
            local varLength="${#varValue}"
            printf -v "$varName" '%*s' "$varLength" ''
            local xString=$(printf '%*s' "$varLength" '' | tr ' ' 'X')
            printf -v "$varName" '%s' "$xString"
        fi
        unset "$varName"
    done

    if [[ -n "$monitorPID" ]];
    then
        if ps "$monitorPID" &>/dev/null;
        then
            log_Message "Killing monitor" "SECURITY"
            if kill "$monitorPID" &>/dev/null;
            then
                log_Message "Monitor killed" "SECURITY"

            else
                log_Message "Monitor not killed. Kill ${monitorPID} in Activity Monitor" "ERROR"
            fi
        else
            log_Message "Monitor PID not found, already exited" "SECURITY"
        fi
    fi
}

function clean_Exit() {
    clean_Env
    if [[ -n "$tAccountPass" ]];
    then
        local varLength="${#tAccountPass}"
        printf -v "tAccountPass" '%*s' "$varLength" ''
        tAccountPass=$(printf '%*s' "$varLength" '' | tr ' ' 'X')
        unset tAccountPass
    fi
    delete_TempAccount
}

function main() {
    trap "clean_Exit" EXIT INT TERM HUP
    printf "Log: $(date "+%F %T") Beginning Token Manager script\n" | tee "$logFile"

    if [[ -z "$tAccountName" ]] || [[ -z "$tAccountPass" ]];
    then
        log_Message "Missing critical arguments" "ERROR"
        exit 1
    fi

    if ! sudo_Check;
    then
        log_Message "Exiting at sudo check" "ERROR"
        exit 1
    fi

    if ! icon_Check;
    then
        alert_Dialog "Missing required icon files!"
        log_Message "Exiting for no icon" "ERROR"
        exit 1
    fi

    returnToDropdown=1
    while [ $returnToDropdown -eq 1 ];
    do
        log_Message "Displaying dropdown dialog"
        if ! dropdown_Prompt "Select the desired Secure Token action:";
        then
            log_Message "Exiting at dropdown dialog"
            returnToDropdown=0
        else
            get_UserArrays
            case "$dropdownPrompt" in
                'Current Token Status')
                    secureTokenCombinedPhrase="${secureTokenPhrase}\n\n${nonSecureTokenPhrase}"
                    log_Message "Displaying Token Status dialog"
                    if ! binary_Dialog "$secureTokenCombinedPhrase";
                    then
                        log_Message "Going back to dropdown dialog"
                    else
                        log_Message "Exiting at Token Status dialog"
                        returnToDropdown=0
                    fi
                    ;;

                'Add Token')
                    log_Message "Displaying first Add Token text field dialog"
                    if ! token_Action_Display "Enter the username of a Secure Token account:\n\n${secureTokenPhrase}" "Enter the username of a Non-Secure Token account:\n\n${nonSecureTokenPhrase}" "$dropdownPrompt";
                    then
                        log_Message "Going back to dropdown dialog"
                    else
                        returnToDropdown=0
                    fi
                    ;;

                'Remove Token')
                    log_Message "Displaying first Remove Token text field dialog"
                    if ! token_Action_Display "Enter the username of an Admin account:\n\n${adminAccountPhrase}" "Enter the username of an account to remove the Secure Token from:\n\n${secureTokenPhrase}" "$dropdownPrompt";
                    then
                        log_Message "Going back to dropdown dialog"
                    else
                        returnToDropdown=0
                    fi
                    ;;

                *)
                    alert_Dialog "Unknown option chosen from dropdown menu!"
                    log_Message "Exiting after option chosen from dropdown dialog" "ERROR"
                    exit 1
                    ;;
            esac
        fi
    done

    log_Message "Exiting!"
    exit 0
}

main

