#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 03-12-25  ###
### Updated: 08-25-25  ###
### Version: 1.5       ###
##########################

readonly defaultIconPath='/usr/local/jamfconnect/SLU.icns'
readonly genericIconPath='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
readonly dialogTitle='Token Manager'
readonly logFile='/var/log/token_Manager.log'

# Check the script is ran with admin privileges
function sudo_Check() {
    if [ "$(id -u)" -ne 0 ];
    then
        alert_Dialog "Please run this script as root or using sudo!"
        exit 1
    fi
}

# Append current status to log file
function log_Message() {
    local timestamp="$(date "+%F %T")"
    printf "Log: %s %s\n" "$timestamp" "$1" | tee -a "$logFile"
}

# Check if account is in the admin group
function admin_Check(){
    local account="$1"
    if /usr/sbin/dseditgroup -o checkmember -m "$account" admin >/dev/null;
    then
        return 0
    else
        return 1
    fi
}

# Check if account exists
function account_Check() {
    local account="$1"
    if /usr/bin/id "$account" >/dev/null;
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
    while [ $count -le 10 ];
    do
        dropdownPrompt=$(/usr/bin/osascript <<OOP
        set promptString to "$promptString"
        set dialogTitle to "$dialogTitle"
        set dropdownOptions to {"Token Status", "Add Token", "Remove Token"}
        set userChoice to (choose from list dropdownOptions with prompt promptString cancel button name "Quit" default items "Token Status" with title dialogTitle)
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
                log_Message "User chose: quit"
                return 1
                ;;
            'TIMEOUT')
                log_Message "Timed out, re-prompting ($count/10)"
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
                return "TIMEOUT"
            end if
        on error
            return "CANCEL"
        end try
OOP
        )
        case "$textFieldDialog" in
            'CANCEL')
                log_Message "User responded with: $textFieldDialog"
                return 1
                ;;
            'TIMEOUT')
                log_Message "No response, re-prompting ($count/10)"
                ((count++))
                ;;
            '')
                log_Message "Nothing entered in text field"
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
        if [[ "$username" == 'daemon' || "$username" == 'nobody' || "$username" == 'root' ]];
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

    log_Message "Secure Token accounts:"
    if [[ ${#secureTokenUserArray[@]} -eq 0 ]];
    then
        secureTokenPhrase=$(printf "Secure Token accounts:\nNone")
        log_Message "None"
    else
        userList=$(printf "%s\n" "${secureTokenUserArray[@]}")
        secureTokenPhrase=$(printf "Secure Token accounts:\n%s" "$userList")
        for user in "${secureTokenUserArray[@]}";
        do
            log_Message " - $user"
        done
    fi

    log_Message "Non-Secure Token accounts:"
    if [[ ${#nonSecureTokenUserArray[@]} -eq 0 ]];
    then
        nonSecureTokenPhrase=$(printf "Non-Secure Token accounts:\nNone")
        log_Message "None"
    else
        userList=$(printf "%s\n" "${nonSecureTokenUserArray[@]}")
        nonSecureTokenPhrase=$(printf "Non-Secure Token accounts:\n%s" "$userList")
        for user in "${nonSecureTokenUserArray[@]}";
        do
            log_Message " - $user"
        done
    fi

    log_Message "Admin accounts:"
    if [[ ${#adminAccountArray[@]} -eq 0 ]];
    then
        adminAccountPhrase=$(printf "Admin accounts:\nNone")
        log_Message "None"
    else
        userList=$(printf "%s\n" "${adminAccountArray[@]}")
        adminAccountPhrase=$(printf "Admin accounts:\n%s" "$userList")
        for user in "${adminAccountArray[@]}";
        do
            log_Message " - $user"
        done
    fi

    log_Message "Admin accounts with Secure Tokens:"
    if [[ ${#secureTokenAdminArray[@]} -eq 0 ]];
    then
        secureTokenAdminPhrase=$(printf "Admin accounts with Secure Tokens:\nNone")
        log_Message "None"
    else
        userList=$(printf "%s\n" "${secureTokenAdminArray[@]}")
        secureTokenAdminPhrase=$(printf "Admin accounts with Secure Tokens:\n%s" "$userList")
        for user in "${secureTokenAdminArray[@]}";
        do
            log_Message " - $user"
        done
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
        log_Message "Error with token action"
        return 1
    fi
    if [[ "$result" == *"Done"* ]];
    then
        return 0
    else
        log_Message "sysadminctl result: ${result}"
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
        log_Message "Exiting at first $tokenActionType text field dialog"
    else
        log_Message "Continued through $tokenActionType text field dialog"
        adminAccount="$textFieldDialog"
        if ! account_Check "$adminAccount";
        then
            log_Message "$adminAccount does not exist"
            alert_Dialog "$adminAccount does not exist!"
            return 1
        fi
        if ! textField_Dialog "$secondPrompt";
        then
            log_Message "Exiting at second $tokenActionType text field dialog"
        else
            log_Message "Continued through second $tokenActionType text field dialog"
            tokenAccount="$textFieldDialog"
            if ! account_Check "$tokenAccount";
            then
                log_Message "$tokenAccount does not exist"
                alert_Dialog "$tokenAccount does not exist!"
                return 1
            fi
            log_Message "Prompting for $adminAccount password"
            if ! textField_Dialog "Enter the password for $adminAccount:" "hidden";
            then
                log_Message "Exiting at first password prompt"
            else
                adminPassword="$textFieldDialog"
                log_Message "Prompting for $tokenAccount password"
                if ! textField_Dialog "Enter the password for $tokenAccount:" "hidden";
                then
                    log_Message "Exiting at second password prompt"
                else
                    tokenPassword="$textFieldDialog"
                    if ! token_Action "$tokenAccount" "$tokenPassword" "$adminAccount" "$adminPassword" "$tokenActionType";
                    then
                        adminPassword=''
                        tokenPassword=''
                        log_Message "$(printf "Error with Secure token action!\nPriviliged Account: %s\nNon-Priviliged Account: %s\nToken Action: %s" "$adminAccount" "$tokenAccount" "$tokenActionType")"
                        alert_Dialog "Error with Secure token action!\n\nPriviliged Account:\n${adminAccount}\n\nNon-Priviliged Account:\n${tokenAccount}\n\nToken Action:\n${tokenActionType}"
                    else
                        adminPassword=''
                        tokenPassword=''
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
                fi
            fi
        fi
    fi
    adminPassword=''
    tokenPassword=''
    return 1
}

function main() {
    sudo_Check
    printf "Log: $(date "+%F %T") Beginning Token Manager script\n" | tee "$logFile"

    if ! icon_Check;
    then
        alert_Dialog "Missing required icon files!"
        log_Message "Exiting for no icon"
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
                'Token Status')
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
                    if ! token_Action_Display "Enter the username of a Secure Token account:\n\n${secureTokenAdminPhrase}" "Enter the username of a Non-Secure Token account:\n\n${nonSecureTokenPhrase}" "$dropdownPrompt";
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
                    log_Message "Error, exiting after option chosen from dropdown dialog"
                    exit 1
                    ;;
            esac
        fi
    done

    log_Message "Exiting!"
    exit 0
}

main
