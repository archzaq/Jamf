#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 8-27-24   ###
### Updated: 8-27-24   ###
### Version: 1.0       ###
##########################

managementAccount="$4"
managementAccountPass="$5"
elevatedAccount="$6"
elevatedAccountPass=""
currentUserPassword=""
readonly elevatedAccountPath="/Users/$elevatedAccount"
readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly logPath='/var/log/elevatedAccount.log'
readonly iconPath='/usr/local/jamfconnect/SLU.icns'
readonly dialogTitle='SLU ITS: Elevated Account Creation'

# Check for SLU icon file, applescript dialog boxes will error without it
function icon_Check() {
    if [[ ! -f "$iconPath" ]];
    then
        echo "Log: $(date "+%F %T") No SLU icon found, attempting install." | tee -a "$logPath"
        /usr/local/bin/jamf policy -event SLUFonts
        if [[ ! -f "$iconPath" ]];
        then
            echo "Log: $(date "+%F %T") No SLU icon found, exiting." | tee -a "$logPath"
            return 1
        fi
    fi
    echo "Log: $(date "+%F %T") SLU icon found, continuing." | tee -a "$logPath"
    return 0
}

# Check if someone is logged into the device
function login_Check() {
    local account="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
    if [[ "$account" == 'root' ]];
    then
        echo "Log: $(date "+%F %T") \"$account\" currently logged in." | tee -a "$logPath"
        return 1
    elif [[ "$account" == 'loginwindow' ]] || [[ -z "$account" ]];
    then
        echo "Log: $(date "+%F %T") No one logged in." | tee -a "$logPath"
        return 1
    else
        echo "Log: $(date "+%F %T") \"$account\" currently logged in." | tee -a "$logPath"
        return 0
    fi
}

# Check if account exists
function account_Check() {
    local account="$1"
    if /usr/bin/id "$account" &>/dev/null;
    then
        echo "Log: $(date "+%F %T") \"$account\" exists." | tee -a "$logPath"
        return 0
    else
        echo "Log: $(date "+%F %T") \"$account\" does not exist." | tee -a "$logPath"
        return 1
    fi
}

# Check if account is in the admin group
function admin_Check(){
    local account="$1"
    local groupList=$(/usr/bin/groups "$account")
    if [[ $groupList == *" admin "* ]];
    then
        echo "Log: $(date "+%F %T") \"$account\" is an admin." | tee -a "$logPath"
        return 0
    else
        echo "Log: $(date "+%F %T") \"$account\" is not an admin." | tee -a "$logPath"
        return 1
    fi
}

# Prompt the user for their password, reprompting if they enter nothing
function password_Prompt(){
    local phrase="$1"
    local readonly passwordTitle='SLU ITS: Password Prompt'
    currentUserPassword=$(/usr/bin/osascript <<OOP
        set currentUserPassword to (display dialog "$phrase:" buttons {"Cancel", "OK"} default button "OK" with hidden answer default answer "" with icon POSIX file "$iconPath" with title "$passwordTitle" giving up after 900)
        if button returned of currentUserPassword is equal to "OK" then
            return text returned of currentUserPassword
        else
            return "timeout"
        end if
OOP
    )
    if [[ $? != 0 ]];
    then
        echo "Log: $(date "+%F %T") User selected cancel." | tee -a "$logPath"
        return 1
    elif [[ -z "$currentUserPassword" ]];
    then
        echo "Log: $(date "+%F %T") No password entered." | tee -a "$logPath"
        /usr/bin/osascript -e 'display alert "An error has occurred" message "You did not enter a password. Please try again." as critical buttons {"OK"} default button "OK" giving up after 900'
        password_Prompt
    elif [[ "$currentUserPassword" == 'timeout' ]];
    then
        echo "Log: $(date "+%F %T") Timed out." | tee -a "$logPath"
        password_Prompt
    else
        echo "$currentUserPassword"
        return 0
    fi
}

# Creates account with a home folder and proper permissions
function create_Account() {
    local accountAdd="$1"
    local accountAddPass="$2"
    local accountAddPath="$3"
    local managementAccount="$4"
    local managementAccountPass="$5"

    if /usr/sbin/sysadminctl -addUser "$accountAdd" -password "$accountAddPass" -home "$accountAddPath" -admin -adminUser "$managementAccount" -adminPassword "$managementAccountPass";
    then
        if account_Check "$accountAdd";
        then
            dirs=("Desktop" "Documents" "Downloads" "Library" "Movies" "Music" "Pictures" "Public")
            for dir in "${dirs[@]}";
            do
                mkdir -p "$accountAddPath/$dir"
            done
            chown -R "$accountAdd":staff "$accountAddPath"
            chmod -R 750 "$accountAddPath"
            chmod -R +a "group:everyone deny delete" "$accountAddPath"
            echo "Log: $(date "+%F %T") \"$accountAdd\" successfully created" | tee -a "$logPath"
            return 0
        else
            echo "Log: $(date "+%F %T") \"$accountAdd\" failed to be created" | tee -a "$logPath"
            return 1
        fi
    else
        echo "Log: $(date "+%F %T") \"$accountAdd\" could not be created." | tee -a "$logPath"
        return 1
    fi
}

# Check user account for volume ownership
function check_Ownership() {
    local account="$1"
    local volumeOwner=false
    local accountGUID=$(/usr/bin/dscl . -read /Users/$account GeneratedUID | awk '{print $2}')
    local systemVolume=$(/usr/sbin/diskutil info / | grep "Volume Name" | sed 's/.*: //' | sed 's/^ *//')
    local systemVolumePath="/Volumes/$systemVolume"
    echo "Log: $(date "+%F %T") Checking \"$account\" for volume ownership." | tee -a "$logPath"
    for id in $(/usr/sbin/diskutil apfs listUsers "$systemVolumePath" | grep -E '.*-.*' | awk '{print $2}');
    do
        if [[ "$id" == "$accountGUID" ]];
        then
            echo "Log: $(date "+%F %T") \"$account\" is a volume owner." | tee -a "$logPath"
            volumeOwner=true
            return 0
        fi
    done
    if [[ "$volumeOwner" != true ]];
    then
        echo "Log: $(date "+%F %T") \"$account\" is not a volume owner." | tee -a "$logPath"
        return 1
    fi
}

# Assigns secure token to current user using management account
function assign_Token(){
    # Test the sysadminctl command for a success before actually attempting to grant a secure token
    # Pretty sure this doesnt actually test and just runs the command straight up
    local secureTokenTest=$(/usr/sbin/sysadminctl -adminUser "$managementAccount" -adminPassword "$managementAccountPass" -secureTokenOn "$currentUser" -password "$currentUserPassword" -test 2>&1)
    if [[ $secureTokenTest == *"Done"* ]];
    then
        /usr/sbin/sysadminctl -adminUser "$managementAccount" -adminPassword "$managementAccountPass" -secureTokenOn "$currentUser" -password "$currentUserPassword"
        echo "Log: $(date "+%F %T") Success assigning secure token!" | tee -a "$logPath"
        return 0
    else
        echo "Log: $(date "+%F %T") Error with sysadminctl command." | tee -a "$logPath"
        return 1
    fi
}

function main() {
    echo "Log: $(date "+%F %T") Beginning elevated account script." | tee "$logPath"

    # Check for SLU icon file
    if ! icon_Check;
    then
        echo "Log: $(date "+%F %T")Exiting for no SLU icon." | tee -a "$logPath"
        exit 1
    fi

    # Check for valid user being logged in
    if ! login_Check;
    then
        echo "Log: $(date "+%F %T")Exiting for invalid user logged in." | tee -a "$logPath"
        exit 1
    fi

    # Check if management account exists
    if ! account_Check "$managementAccount";
    then
        echo "Log: $(date "+%F %T")Management account does not exist, exiting." | tee -a "$logPath"
        /usr/bin/osascript -e 'display alert "An error has occurred" message "Management account does not exist. Unable to proceed with account creation." as critical buttons {"OK"} default button "OK" giving up after 900'
        exit 1
    fi

    # Check if management account is an admin
    if ! admin_Check "$managementAccount";
    then
        echo "Log: $(date "+%F %T")Management account is not an admin, exiting." | tee -a "$logPath"
        /usr/bin/osascript -e 'display alert "An error has occurred" message "Management account is not an admin. Unable to proceed with account creation." as critical buttons {"OK"} default button "OK" giving up after 900'
        exit 1
    fi

    # Prompt user for elevated account password
    elevatePassResult=$(password_Prompt "Please enter the password you would like to use for the elevated account:")
    elevatePassStatus=$?
    echo "Log: $(date "+%F %T") Prompting user for elevated account password." | tee -a "$logPath"
    if [[ $elevatePassStatus -ne 0 ]];
    then
        echo "Log: $(date "+%F %T") Exiting at password prompt." | tee -a "$logPath"
        exit 1
    fi
    echo "Log: $(date "+%F %T") Password prompt finished." | tee -a "$logPath"
    elevatedAccountPass="$elevatedPassResult"

    # Attempt to create elevated account using management account
    if ! create_Account "$elevatedAccount" "$elevatedAccountPass" "$elevatedAccountPath" "$managementAccount" "$managementAccountPass";
    then
        echo "Log: $(date "+%F %T") Exiting at account creation." | tee -a "$logPath"
        /usr/bin/osascript -e 'display alert "An error has occurred" message "There was an issue with the account creation. Unable to proceed." as critical buttons {"OK"} default button "OK" giving up after 900'
        exit 1
    fi

    # Check user for secure token, assign one using management account, if possible
    if ! check_Ownership "$currentUser";
    then
        if ! check_Ownership "$managementAccount";
        then
            echo "Log: $(date "+%F %T") Attempting to assign secure token to \"$currentUser\" using the management account." | tee -a "$logPath"

            # Prompt the user for their password
            userPassResult=$(password_Prompt "Please enter your computer password:")
            userPassStatus=$?
            echo "Log: $(date "+%F %T") Prompting user for their password." | tee -a "$logPath"
            if [[ $userPassStatus -ne 0 ]];
            then
                echo "Log: $(date "+%F %T") Exiting at password prompt." | tee -a "$logPath"
                exit 1
            fi
            echo "Log: $(date "+%F %T") Password prompt finished." | tee -a "$logPath"
            currentUserPassword="$userPassResult"

            # Attempt to assign secure token
            if ! assign_Token;
            then
                echo "Log: $(date "+%F %T") Management account unable to grant a secure token, exiting." | tee -a "$logPath"
            fi
        else
            echo "Log: $(date "+%F %T") Management account does not have volume ownership, exiting." | tee -a "$logPath"
        fi
    fi

    exit 0
}

main

