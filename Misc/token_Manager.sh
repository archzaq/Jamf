#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 3-12-25   ###
### Updated: 3-13-25   ###
### Version: 1.3       ###
##########################

readonly defaultIconPath='/usr/local/jamfconnect/SLU.icns'
readonly genericIconPath='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
readonly dialogTitle='Token Manager'
readonly logPath='/var/log/token_Manager.log'

# Check the script is ran with admin privileges
function sudo_Check() {
    if [ "$(id -u)" -ne 0 ];
    then
        echo "Please run this script as root or using sudo!"
        exit 1
    fi
}

# Check if account is in the admin group
function admin_Check(){
    local account="$1"
    local groupList=$(/usr/bin/groups "$account")
    if [[ $groupList == *" admin "* ]];
    then
        return 0
    else
        return 1
    fi
}

# Check for valid icon file, AppleScript dialog boxes will error without it
function icon_Check() {
    effectiveIconPath="$defaultIconPath"
    if [[ ! -f "$effectiveIconPath" ]];
    then
        log_Message "No SLU icon found."
        if [[ -f '/usr/local/bin/jamf' ]];
        then
            log_Message "Attempting icon install via Jamf."
            /usr/local/bin/jamf policy -event SLUFonts
        else
            log_Message "No Jamf binary found."
        fi
        if [[ ! -f "$effectiveIconPath" ]];
        then
            if [[ -f "$genericIconPath" ]];
            then
                log_Message "Generic icon found."
                effectiveIconPath="$genericIconPath"
            else
                log_Message "Generic icon not found."
                return 1
            fi
        fi
    else
        log_Message "SLU icon found."
    fi
    return 0
}

# AppleScript - Ask user to choose from a list of items
function dropdown_Prompt() {
    local promptString="$1"
    local count=1
    while [ $count -le 10 ];
    do
        dropdownPrompt=$(/usr/bin/osascript <<OOP
        set promptString to "$promptString"
        set dialogTitle to "$dialogTitle"
        set dropdownOptions to {"Token Status", "Add Token", "Remove Token"}
        set userChoice to (choose from list dropdownOptions with prompt promptString default items "Token Status" with title dialogTitle)
        if userChoice is false then
            return "cancelled"
        else if userChoice is {} then
            return "timeout"
        else
            return (item 1 of userChoice)
        end if
OOP
        )
        case "$dropdownPrompt" in
            'cancelled')
                log_Message "User selected cancel."
                return 1
                ;;
            'timeout')
                log_Message "Timed out, re-prompting ($count/10)."
                ((count++))
                ;;
            *)
                log_Message "User chose: $dropdownPrompt"
                return 0
                ;;
        esac
    done
}

# AppleScript - Informing the user and giving them two choices
function binary_Dialog() {
    local promptString="$1"
    local count=1
    while [ $count -le 10 ];
    do
        binDialog=$(/usr/bin/osascript <<OOP
        try
            set promptString to "$promptString"
            set iconPath to "$effectiveIconPath"
            set dialogTitle to "$dialogTitle"
            set dialogResult to display dialog promptString buttons {"Go Back", "Done"} default button "Done" with icon POSIX file iconPath with title dialogTitle giving up after 900
            set buttonChoice to button returned of dialogResult
            if buttonChoice is equal to "" then
                return "timeout"
            else
                return buttonChoice
            end if
        on error
            return "Cancel"
        end try
OOP
        )
        case "$binDialog" in
            'Cancel' | 'Go Back')
                log_Message "User responded with: $binDialog"
                return 1
                ;;
            'timeout')
                log_Message "No response, re-prompting ($count/10)."
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
                log_Message "No response, re-prompting ($count/10)."
                ((count++))
                ;;
            '')
                log_Message "Nothing entered, re-prompting."
                ((count++))
                ;;
            *)
                if [[ "$dialogType" == 'hidden' ]];
                then
                    log_Message "Password entered."
                else
                    log_Message "User responded with: $textFieldDialog"
                fi
                return 0
                ;;
        esac
    done
    return 1
}

# Get an array of Secure Token accounts
function get_SecureTokenArray() {
    secureTokenUserArray=()
    log_Message "Secure Token Users:"
    for id in $(/usr/sbin/diskutil apfs listUsers / | grep -E '.*-.*' | awk '{print $2}');
    do
        username="$(/usr/bin/dscl . -search /Users GeneratedUID ${id} | /usr/bin/awk 'NR==1{print $1}')"
        if [[ ! -z "$username" && ! "$username" == '_'* ]];
        then
            secureTokenUserArray+=( "$username" )
            log_Message " - $username"
        fi
    done
    if [[ -z "$secureTokenUserArray" ]];
    then
        log_Message " - None"
        userList="Secure Token accounts:\nNone"
        secureTokenPhrase=$(echo "$userList")
    else
        userList=$(printf "%s\n" "${secureTokenUserArray[@]}")
        secureTokenPhrase=$(echo -e "Secure Token accounts:\n$userList")
    fi
}

# Get an array of Non-Secure Token accounts
function get_NonSecureTokenArray() {
    nonSecureTokenUserArray=()
    log_Message "Non-Secure Token Users:"
    for username in $(/usr/bin/dscl . -list /Users | grep -v ^_.*);
    do
        if [[ ! "$username" == '_'* && ! "$username" == 'daemon' && ! "$username" == 'nobody' && ! "$username" == 'root' ]];
        then
            if ! printf '%s\n' "${secureTokenUserArray[@]}" | grep -q "^$username$";
            then
                nonSecureTokenUserArray+=( "$username" )
                log_Message " - $username"
            fi
        fi
    done
    if [[ -z "$nonSecureTokenUserArray" ]];
    then
        log_Message " - None"
        userList="Non-Secure Token accounts:\nNone"
        nonSecureTokenPhrase=$(echo "$userList")
    else
        userList=$(printf "%s\n" "${nonSecureTokenUserArray[@]}")
        nonSecureTokenPhrase=$(echo -e "Non-Secure Token accounts:\n$userList")
    fi
}

# Get an array of Admin accounts
function get_AdminAccountArray() {
    adminAccountArray=()
    log_Message "Admin Users:"
    for username in $(/usr/bin/dscl . -list /Users | grep -v ^_.*);
    do
        if [[ ! "$username" == '_'* && ! "$username" == 'daemon' && ! "$username" == 'nobody' && ! "$username" == 'root' ]];
        then
            if admin_Check "$username";
            then
                adminAccountArray+=( "$username" )
                log_Message " - $username"
            fi
        fi
    done
    if [[ -z "$adminAccountArray" ]];
    then
        log_Message " - None"
        userList="Admin accounts:\nNone"
        adminAccountPhrase=$(echo "$userList")
    else
        userList=$(printf "%s\n" "${adminAccountArray[@]}")
        adminAccountPhrase=$(echo -e "Admin accounts:\n$userList")
    fi
}

# Function for adding and removing Secure Tokens
function token_Action() {
    local tokenAccount="$1"
    local tokenPassword="$2"
    local adminAccount="$3"
    local adminPassword="$4"
    local tokenAction="$5"
    if [[ "$tokenAction" == 'Add Token' ]];
    then
        local result=$(su "$adminAccount" -c "/usr/sbin/sysadminctl -secureTokenOn \"$tokenAccount\" -password \"$tokenPassword\" -adminUser \"$adminAccount\" -adminPassword \"$adminPassword\"" 2>&1)
    elif [[ "$tokenAction" == 'Remove Token' ]];
    then
        local result=$(su "$adminAccount" -c "/usr/sbin/sysadminctl -secureTokenOff \"$tokenAccount\" -password \"$tokenPassword\" -adminUser \"$adminAccount\" -adminPassword \"$adminPassword\"" 2>&1)
    else
        log_Message "Error with token action."
        return 1
    fi
    if [[ "$result" == *"Done"* ]];
    then
        return 0
    else
        return 1
    fi
}

# Main logic of Secure Token action being taken
function token_Action_Display() {
    local firstPrompt="$1"
    local secondPrompt="$2"
    local tokenActionType="$3"
    if ! textField_Dialog "$firstPrompt"
    then
        log_Message "Exiting at first $tokenActionType text field dialog."
    else
        log_Message "Continued through $tokenActionType text field dialog."
        adminAccount="$textFieldDialog"
        if ! textField_Dialog "$secondPrompt";
        then
            log_Message "Exiting at second $tokenActionType text field dialog."
        else
            log_Message "Continued through second $tokenActionType text field dialog."
            tokenAccount="$textFieldDialog"
            log_Message "Prompting for password."
            if ! textField_Dialog "Enter the password for $adminAccount:" "hidden";
            then
                log_Message "Exiting at first password prompt."
            else
                adminPassword="$textFieldDialog"
                log_Message "Prompting for password."
                if ! textField_Dialog "Enter the password for $tokenAccount:" "hidden";
                then
                    log_Message "Exiting at second password prompt."
                else
                    tokenPassword="$textFieldDialog"
                    if ! token_Action "$tokenAccount" "$tokenPassword" "$adminAccount" "$adminPassword" "$tokenActionType";
                    then
                        log_Message "Error with Secure Token action."
                    else
                        log_Message "$tokenActionType completed!"
                        log_Message "Displaying Token Status dialog."
                        get_SecureTokenArray
                        get_NonSecureTokenArray
                        secureTokenCombinedPhrase="${secureTokenPhrase}\n\n${nonSecureTokenPhrase}"
                        if ! binary_Dialog "Process completed successfully!\n\n${secureTokenCombinedPhrase}";
                        then
                            log_Message "Going back to dropdown dialog."
                        else
                            log_Message "Exiting at Token Status dialog."
                            return 0
                        fi
                    fi
                fi
            fi
        fi
    fi
    return 1
}

# Append current status to log file
function log_Message() {
    echo "Log: $(date "+%F %T") $1" | tee -a "$logPath"
}

function main() {
    sudo_Check
    echo "Log: $(date "+%F %T") Beginning Token Manager script." | tee "$logPath"

    if ! icon_Check;
    then
        log_Message "Exiting for no icon."
        exit 1
    fi

    returnToDropdown=1
    while [ $returnToDropdown -eq 1 ];
    do
        log_Message "Displaying dropdown dialog."
        if ! dropdown_Prompt "Select the desired Secure Token action:";
        then
            log_Message "Exiting at dropdown dialog."
            exit 0
        fi

        get_SecureTokenArray
        get_NonSecureTokenArray
        get_AdminAccountArray
        case "$dropdownPrompt" in
            'Token Status')
                secureTokenCombinedPhrase="${secureTokenPhrase}\n\n${nonSecureTokenPhrase}"
                log_Message "Displaying Token Status dialog."
                if ! binary_Dialog "$secureTokenCombinedPhrase";
                then
                    log_Message "Going back to dropdown dialog."
                else
                    log_Message "Exiting at Token Status dialog."
                    returnToDropdown=0
                fi
                ;;

            'Add Token')
                log_Message "Displaying first Add Token text field dialog."
                if ! token_Action_Display "Enter the username of a Secure Token account:\n\n${secureTokenPhrase}" "Enter the username of a Non-Secure Token account:\n\n${nonSecureTokenPhrase}" "$dropdownPrompt";
                then
                    log_Message "Going back to dropdown prompt."
                else
                    returnToDropdown=0
                fi
                ;;

            'Remove Token')
                log_Message "Displaying first Remove Token text field dialog."
                if ! token_Action_Display "Enter the username of an Admin account:\n\n${adminAccountPhrase}" "Enter the username of an account to remove the Secure Token from:\n\n${secureTokenPhrase}" "$dropdownPrompt";
                then
                    log_Message "Going back to dropdown prompt."
                else
                    returnToDropdown=0
                fi
                ;;

            *)
                log_Message "Error, exiting after option chosen from dropdown prompt."
                exit 1
                ;;
        esac
    done

    log_Message "Exiting!"
    exit 0
}

main
