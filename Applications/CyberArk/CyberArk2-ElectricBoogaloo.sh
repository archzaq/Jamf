#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 6-6-24    ###
### Updated: 9-20-24   ###
### Version: 2.4       ###
##########################

managementAccount="$4"
managementAccountPass="$5"
managementAccountPath="/Users/$managementAccount"
tempAccount="$6"
tempAccountPassword="$7"
#loggedInUser="$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)"
#loggedInUserPassword=''
currentUserPassword=''
readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly logPath='/var/log/cyberarkFix.log'
readonly iconPath="/usr/local/jamfconnect/SLU.icns"
readonly dialogTitle="SLU ITS: CyberArk Installation"

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

# Add user to admin group using temp account credentials
function add_Account_To_AdminGroup() {
    local account="$1"

    /usr/sbin/dseditgroup -o edit -a "$account" -u "$tempAccount" -P "$tempAccountPassword" -t user -L admin 

    # Double checks user to be in the admin group
    if admin_Check "$account";
    then
        return 0
    else
        return 1
    fi
}

# Check if account has secure token
function secure_Token_Check() {
    local account="$1"

    if /usr/sbin/sysadminctl -secureTokenStatus "$account" 2>&1 | grep -q 'ENABLED';
    then
        echo "Log: \"$account\" has a secure token"
        return 0
    else
        echo "Log: \"$account\" does not have a secure token"
        return 1
    fi
}

# Prompt the user for their password, reprompting if they enter nothing
function password_Prompt(){
    local phrase="$1"
    local readonly passwordTitle='SLU ITS: Password Prompt'
    echo "Log: $(date "+%F %T") Prompting user for their password." | tee -a "$logPath"
    currentUserPassword=$(/usr/bin/osascript <<OOP
        set currentUserPassword to (display dialog "$phrase" buttons {"Cancel", "OK"} default button "OK" with hidden answer default answer "" with icon POSIX file "$iconPath" with title "$passwordTitle" giving up after 900)
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
        /usr/bin/osascript -e "display dialog \"Error! You did not enter a password. Please try again.\" buttons {\"OK\"} default button \"OK\" with icon POSIX file \"$iconPath\" with title \"$passwordTitle\""
        password_Prompt "$phrase"
    elif [[ "$currentUserPassword" == 'timeout' ]];
    then
        echo "Log: $(date "+%F %T") Timed out." | tee -a "$logPath"
        password_Prompt "$phrase"
    fi
    echo "Log: $(date "+%F %T") Password prompt finished." | tee -a "$logPath"
    return 0
}

# Assigns secure token to current user using management account
function assign_Token(){
    # Test the sysadminctl command for a success before actually attempting to grant a secure token
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

# Creates account with a home folder and proper permissions
function create_Account() {
    local accountAdd="$1"
    local accountAddPass="$2"
    local accountAddPath="$3"
    local managementAccount="$4"
    local managementAccountPass="$5"
    if /usr/sbin/sysadminctl -addUser "$accountAdd" -password "$accountAddPass" -home "$accountAddPath" -admin -adminUser "$managementAccount" -adminPassword "$managementAccountPass";
    then
        echo "Log: $(date "+%F %T") \"$accountAdd\" created." | tee -a "$logPath"
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
            echo "Log: $(date "+%F %T") \"$accountAdd\" successfully configured." | tee -a "$logPath"
            return 0
        else
            echo "Log: $(date "+%F %T") \"$accountAdd\" failed to be configured." | tee -a "$logPath"
            return 1
        fi
    else
        echo "Log: $(date "+%F %T") \"$accountAdd\" could not be created." | tee -a "$logPath"
        return 1
    fi
}

# Gather an array of user accounts with secure tokens to be displayed as a list in check_LoggedInUser_Ownership
function gather_SecureToken_UserList() {
    secureTokenUserArray=()
    userList=""
    for user in $(ls /Users/ | grep -vE '^(Shared|loginwindow|\..*)');
    do
        username=$(/usr/bin/basename "$user")
        if secure_Token_Check "$username";
        then
            secureTokenUserArray+=("$username")
        fi
    done
    if [[ -z "$secureTokenUserArray" ]];
    then
        userList="No secure token accounts available.\n\nPlease contact the IT Service Desk at (314)-977-4000."
        phrase=$(echo "$userList")
    else
        userList=$(printf "%s\n" "${secureTokenUserArray[@]}")
        phrase=$(echo -e "Log in as one of the following accounts:\n$userList")
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

# Dialog box to inform user of the overall process taking place
function user_Prompt() {
    if [[ $promptCounter -ge 5 ]];
    then
        echo "Log: Prompted five times with no response, exiting"
        return 1
    fi

    userPrompt=$(osascript <<OOP
    set userPrompt to (display dialog "You are about to receive CyberArk, a SLU-standard security application.\n\nYou will be prompted for your password before the installation may begin.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000." buttons {"Continue"} default button "Continue" with icon POSIX file "$icon" with title "$title" giving up after 900)
    if button returned of userPrompt is equal to "Continue" then
        return "Continue"
    else
        return "timeout"
    end if
OOP
    )
    if [[ "$userPrompt" == 'Continue' ]];
    then
        echo "Log: User selected \"Continue\" through the first dialog box"
        return 0
    else
        echo "Log: Reprompting user with the first dialog box"
        ((promptCounter++))
        user_Prompt
    fi
}

# Final check to make sure management account is ready for CyberArk install
function final_Check() {
    local account="$1"
    
    if account_Check "$account" && admin_Check "$account" && secure_Token_Check "$account";
    then
        echo "Log: Final check passed! CyberArk ready for install"
        return 0
    else
        echo "Log: Final check failed!!"
        return 1
    fi
}

# Check to delete temporary account before exiting
function exitError() {
    if account_Check "$tempAccount";
    then
        /usr/sbin/sysadminctl -deleteUser "$tempAccount" -secure
    fi
    exit 1
}

function main() {
    promptCounter=0
    echo "Log: $(date "+%F %T") Beginning CyberArk fix script." | tee "$logPath"

    # Check for SLU icon file
    echo "Log: $(date "+%F %T") Checking for SLU icon." | tee -a "$logPath"
    if ! icon_Check;
    then
        echo "Log: $(date "+%F %T") Exiting for no SLU icon." | tee -a "$logPath"
        exitError
    fi
    echo "Log: $(date "+%F %T") Check for SLU icon complete." | tee -a "$logPath"



    # Check for valid user being logged in
    echo "Log: $(date "+%F %T") Checking for currently logged in user." | tee -a "$logPath"
    if ! login_Check;
    then
        echo "Log: $(date "+%F %T")Exiting for invalid user logged in." | tee -a "$logPath"
        exitError
    fi
    echo "Log: $(date "+%F %T") Check for currently logged in user complete." | tee -a "$logPath"



    # Check if temp account exists
    echo "Log: $(date "+%F %T") Checking for temporary account." | tee -a "$logPath"
    if ! account_Check "$tempAccount";
    then
        echo "Log: $(date "+%F %T")Temporary account does not exist, exiting." | tee -a "$logPath"
        exitError
    fi
    echo "Log: $(date "+%F %T") Check for temporary account complete." | tee -a "$logPath"



    # Check if management account exists, create it if not
    echo "Log: $(date "+%F %T") Checking for \"$managementAccount\"." | tee -a "$logPath"
    if ! account_Check "$managementAccount";
    then
        if ! create_Account "$managementAccount" "$managementAccountPass" "$managementAccountPath" "$tempAccount" "$tempAccountPassword";
        then
            echo "Log: $(date "+%F %T") Exiting at account creation." | tee -a "$logPath"
            /usr/bin/osascript -e 'display alert "An error has occurred" message "There was an issue with creating management account. Unable to proceed." as critical buttons {"OK"} default button "OK" giving up after 900'
            exitError
        fi
        echo "Log: $(date "+%F %T") Creation of \"$managementAccount\" complete." | tee -a "$logPath"
    fi
    echo "Log: $(date "+%F %T") Check for \"$managementAccount\" complete." | tee -a "$logPath"



    # Prompt user with the action to take place
    if ! user_Prompt;
    then
        exitError
    fi

    # If management account is not an admin, assign it to admin group using temp account credentials
    if ! admin_Check "$managementAccount";
    then
        if ! add_Account_To_AdminGroup "$managementAccount";
        then
            exitError
        fi
    fi

    # Gather list of secure token accounts to display if loggedInUser doesnt have one
    gather_SecureToken_UserList
    if ! check_LoggedInUser_Ownership;
    then
        exitError
    fi

    # If management account doesnt have a secure token, ask for their password, then grant admin only to assign a token
    if ! secure_Token_Check "$managementAccount";
    then
        if ! admin_Check "$loggedInUser";
        then
            if ! password_Prompt;
            then
                exitError
            fi

            if add_Account_To_AdminGroup "$loggedInUser";
            then
                assign_Token
                /usr/sbin/dseditgroup -o edit -d "$loggedInUser" -u "$tempAccount" -P "$tempAccountPassword" -t user -L admin
            else
                echo "Log: Failed to add \"$loggedInUser\" to admin group"
                exitError
            fi
        else
            if ! password_Prompt;
            then
                exitError
            fi
            assign_Token
        fi
    fi

    # Final check to make sure management account is ready for CyberArk install
    if final_Check "$managementAccount";
    then
        /usr/sbin/sysadminctl -deleteUser "$tempAccount" -secure
        /usr/bin/osascript -e "display dialog \"Excellent!\\n\\nBeginning installation of CyberArk now.\" buttons {\"OK\"} default button \"OK\" with icon POSIX file \"$icon\" with title \"$title\""
        /usr/local/bin/jamf policy -event CyberArk
        exit 0
    else
        /usr/bin/osascript -e 'display alert "An error has occurred" message "Management account has not been granted the proper permissions.\n\nDouble check your password." as critical buttons {"OK"} default button "OK"'
        main
    fi
}

main
