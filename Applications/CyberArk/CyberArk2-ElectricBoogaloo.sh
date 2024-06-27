#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 6-6-24    ###
### Updated: 6-27-24   ###
### Version: 2.3       ###
##########################

managementAccount="$4"
managementAccountPass="$5"
managementAccountPath="/Users/$managementAccount"
tempAccount="$6"
tempAccountPassword="$7"
loggedInUser="$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)"
loggedInUserPassword=''
title="SLU ITS: CyberArk Installation"
icon="/usr/local/jamfconnect/SLU.icns"

# Check if someone is logged into the device
function login_Check() {
    local account="$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"

    if [[ "$account" == 'root' ]];
    then
        echo "Log: \"$account\" currently logged in"
        return 1
    elif [[ "$account" == 'loginwindow' ]] || [[ -z "$account" ]];
    then
        echo "Log: No one logged in"
        return 1
    else
        echo "Log: \"$account\" currently logged in"
        return 0
    fi
}

# Check for SLU icon, otherwise the osascript calls will fail
function icon_Check() {
    if [[ ! -f "$icon" ]];
    then
        /usr/local/bin/jamf policy
        if [[ ! -f "$icon" ]];
        then
            echo "Log: No SLU icon installed, exiting."
            return 1
        fi
    fi

    return 0
}

# Check if account exists
function account_Check() {
    local account="$1"

    if id "$account" &>/dev/null;
    then
        echo "Log: \"$account\" exists"
        return 0
    else
        echo "Log: \"$account\" does not exist"
        return 1
    fi
}

# Check if account is in the admin group
function admin_Check(){
    local account="$1"
    local groupList=$(/usr/bin/groups "$account")

    if [[ $groupList == *" admin "* ]];
    then
        echo "Log: \"$account\" is an admin"
        return 0
    else
        echo "Log: \"$account\" is not an admin"
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

# Prompt the user for their password, reprompting if they enter nothing or the dialog times out
function password_Prompt(){
    local passTitle="SLU ITS: Password Prompt"
    echo "Log: Prompting for password"

    loggedInUserPassword=$(/usr/bin/osascript <<OOP
    set loggedInUserPassword to (display dialog "Please enter your computer password to continue with the installation:" buttons {"OK"} default button "OK" with hidden answer default answer "" with icon POSIX file "$icon" with title "$passTitle" giving up after 900)
    if button returned of loggedInUserPassword is equal to "OK" then
        return text returned of loggedInUserPassword
    else
        return "timeout"
    end if
OOP
	)
    lowerPass=$(echo "$loggedInUserPassword" | tr '[:upper:]' '[:lower:]')
    if [[ -z "$loggedInUserPassword" ]];
    then
        echo "Log: No password entered"
        /usr/bin/osascript -e "display dialog \"Error! You did not enter a password. Please try again.\" buttons {\"OK\"} default button \"OK\" with icon POSIX file \"$icon\" with title \"$passTitle\""
        password_Prompt
    elif [[ "$lowerPass" == 'cancel' ]];
    then
        echo "Log: User used hidden exit"
        return 1
    elif [[ "$loggedInUserPassword" == 'timeout' ]];
    then
        echo "Log: Timed out"
        password_Prompt
    fi

    return 0
}

# Assigns secure token to management account
function assign_Token(){
    # Test the sysadminctl command for a success before actually attempting to grant a secure token
    output=$(/usr/sbin/sysadminctl -adminUser "$loggedInUser" -adminPassword "$loggedInUserPassword" -secureTokenOn "$managementAccount" -password "$managementAccountPass" -test 2>&1)

    # If the test was successful, assign management account a secure token
    if [[ $output == *"Done"* ]];
    then
        /usr/sbin/sysadminctl -adminUser "$loggedInUser" -adminPassword "$loggedInUserPassword" -secureTokenOn "$managementAccount" -password "$managementAccountPass"
        echo "Log: Success!!"
        return 0

    # If the test was not successful, exit
    else
        echo "Log: Error with sysadminctl command"
        return 1
    fi
}

# Creates management account with a home folder with proper permissions
function create_ManagementAccount() {
    /usr/sbin/sysadminctl -addUser "$managementAccount" -password "$managementAccountPass" -home "$managementAccountPath" -admin -adminUser "$tempAccount" -adminPassword "$tempAccountPassword"
    if account_Check "$managementAccount";
    then
        dirs=("Desktop" "Documents" "Downloads" "Library" "Movies" "Music" "Pictures" "Public")
        for dir in "${dirs[@]}";
        do
            mkdir -p "$managementAccountPath/$dir"
        done
        chown -R "$managementAccount":staff "$managementAccountPath"
        chmod -R 750 "$managementAccountPath"
        chmod -R +a "group:everyone deny delete" "$managementAccountPath"
        echo "Log: \"$managementAccount\" successfully created"
        return 0
    else
        echo "Log: \"$managementAccount\" failed to be created"
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

# Check current user for volume ownership
function check_LoggedInUser_Ownership() {
    loggedInUserGUID=$(/usr/bin/dscl . -read /Users/$loggedInUser GeneratedUID | awk '{print $2}')
    systemVolume=$(/usr/sbin/diskutil info / | grep "Volume Name" | sed 's/.*: //' | sed 's/^ *//')
    systemVolumePath="/Volumes/$systemVolume"

    for id in $(/usr/sbin/diskutil apfs listUsers "$systemVolumePath" | grep -E '.*-.*' | awk '{print $2}');
    do
        if [[ "$id" == "$loggedInUserGUID" ]];
        then
            echo "Log: \"$loggedInUser\" has volume ownership"
            return 0
        fi
    done

    echo "Log: \"$loggedInUser\" does not have volume ownership"
    /usr/bin/osascript -e "display dialog \"You are not a volume owner! Your account does not have the proper permission to continue.\n\n$phrase\" buttons {\"OK\"} default button \"OK\" with icon POSIX file \"$icon\" with title \"$title\""
    return 1
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

function main() {
    promptCounter=0

    # Ensure someone is logged into the GUI before running 
    if ! login_Check;
    then
        /usr/sbin/sysadminctl -deleteUser "$tempAccount" -secure
        exit 1
    fi

    # Ensure SLU icon is present
    if ! icon_Check;
    then
        /usr/sbin/sysadminctl -deleteUser "$tempAccount" -secure
        exit 1
    fi

    # Ensure temp account is present
    if ! account_Check "$tempAccount";
    then
        /usr/sbin/sysadminctl -deleteUser "$tempAccount" -secure
        exit 1
    fi

    # Prompt user with the action to take place
    if ! user_Prompt;
    then
        /usr/sbin/sysadminctl -deleteUser "$tempAccount" -secure
        exit 1
    fi

    # If management account does not exist, create it
    if ! account_Check "$managementAccount";
    then
        if ! create_ManagementAccount;
        then
            /usr/sbin/sysadminctl -deleteUser "$tempAccount" -secure
            exit 1
        fi
    fi

    # If management account is not an admin, assign it to admin group using temp account credentials
    if ! admin_Check "$managementAccount";
    then
        if ! add_Account_To_AdminGroup "$managementAccount";
        then
            /usr/sbin/sysadminctl -deleteUser "$tempAccount" -secure
            exit 1
        fi
    fi

    # Gather list of secure token accounts to display if loggedInUser doesnt have one
    gather_SecureToken_UserList
    if ! check_LoggedInUser_Ownership;
    then
        /usr/sbin/sysadminctl -deleteUser "$tempAccount" -secure
        exit 1
    fi

    # If management account doesnt have a secure token, ask for their password, then grant admin only to assign a token
    if ! secure_Token_Check "$managementAccount";
    then
        if ! admin_Check "$loggedInUser";
        then
            if ! password_Prompt;
            then
                /usr/sbin/sysadminctl -deleteUser "$tempAccount" -secure
                exit 1
            fi

            if add_Account_To_AdminGroup "$loggedInUser";
            then
                assign_Token
                /usr/sbin/dseditgroup -o edit -d "$loggedInUser" -u "$tempAccount" -P "$tempAccountPassword" -t user -L admin
            else
                echo "Log: Failed to add \"$loggedInUser\" to admin group"
                /usr/sbin/sysadminctl -deleteUser "$tempAccount" -secure
                exit 1
            fi
        else
            if ! password_Prompt;
            then
                /usr/sbin/sysadminctl -deleteUser "$tempAccount" -secure
                exit 1
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
        /usr/bin/osascript -e 'display alert "An error has occurred" message "Management account has not been granted the proper permissions." as critical buttons {"OK"} default button "OK"'
        main
    fi
}

main
