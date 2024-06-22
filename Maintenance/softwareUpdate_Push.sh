#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 6-21-24   ###
### Updated: 6-21-24   ###
### Version: 1.0       ###
##########################

updateCount=0
currentUser="$(defaults read /Library/Preferences/com.apple.loginwindow lastUserName)"

# Check for SLU icon file
function icon_Check() {
    if [[ ! -f "/usr/local/jamfconnect/SLU.icns" ]];
    then
        /usr/local/bin/jamf policy -event SLUFonts
        if [[ ! -f "/usr/local/jamfconnect/SLU.icns" ]];
        then
        	echo "Log: No SLU icon installed, exiting."
            return 1
        fi
    fi
    return 0
}

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

# Check for any OS updates and store them in $macOSAvailableUpgrades
# Also counts how many updates available
function update_Check() {
    result=$(/usr/sbin/softwareupdate -l)
    echo "Available updates:"
    echo "$result"

    macOSAvailableUpgrades=$(echo "$result" | grep "Label: macOS")
    if [[ "$macOSAvailableUpgrades" == '' ]];
    then
        echo "Log: No updates available."
	    osascript -e "display dialog \"Your device's OS is fully up to date! Thank you.\" buttons {\"OK\"} default button \"OK\" with icon POSIX file \"/usr/local/jamfconnect/SLU.icns\" with title \"SLU ITS: OS Update\""
        return 1
    fi
    cleanUpdateList=$(echo "$macOSAvailableUpgrades" | awk '{print $3,$4,$5}')

    echo "macOS updates:"
    echo "$cleanUpdateList"
    
    # Loop through each line of $macOSAvailableUpgrades
    while IFS= read -r line;
    do
        updateCount=$((updateCount + 1))
    done <<< "$macOSAvailableUpgrades"

    echo ""
    echo "Total macOS updates available: $updateCount"
    return 0
}

# Dialog box to inform user of the overall process taking place
function user_Prompt() {
    if [[ $promptCounter -ge 5 ]];
    then
        echo "Log: Prompted five times with no response, exiting"
        return 1
    fi

    if [[ $(uname -p) == 'arm' ]];
    then
        prompt="\n\nYou will be prompted for your password before the installation may begin."
    else
        prompt=''
    fi

    userPrompt=$(osascript <<OOP
    set userPrompt to (display dialog "You are about to receive an OS upgrade.$prompt\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000." buttons {"Continue"} default button "Continue" with icon POSIX file "/usr/local/jamfconnect/SLU.icns" with title "SLU ITS: OS Update" giving up after 900)
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

# Inform the user of how many updates they currently have
function prompt_User() {
    promptMessage=""
    if ((updateCount > 1));
    then
        promptMessage="You have more than one OS update available, you will need to run this policy for each available update.\n\nAvailable Updates:\n$cleanUpdateList\n\nYour device will restart when the download is complete. Save all of your files before proceeding.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000."
    elif ((updateCount == 1));
    then
        promptMessage="You have one OS update available.\n\nAvailable Update:\n$cleanUpdateList\n\nYour device will restart when the download is complete. Save all of your files before proceeding.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000."
    fi

    userPrompt=$(osascript <<OOP
    set dialogResult to (display dialog "$promptMessage" buttons {"Begin Download and Install"} default button "Begin Download and Install" with icon POSIX file "/usr/local/jamfconnect/SLU.icns" with title "SLU ITS: OS Update" giving up after 900)
    if button returned of dialogResult is equal to "Begin Download and Install" then
        return "Begin Download and Install"
    else
        return "timeout"
    end if
OOP
    )
    if [[ "$userPrompt" == "timeout" ]];
    then
        echo "Log: Timed out. Reprompting."
        prompt_User
    fi
    return 0
}

# Prompt the user for their password, reprompting if they enter nothing
function password_Prompt(){
	echo "Log: Prompting user for their password"
	currentUserPassword=$(osascript <<OOP
	    set currentUserPassword to (display dialog "Please enter your computer password to continue with OS update:" buttons {"OK"} default button "OK" with hidden answer default answer "" with icon POSIX file "/usr/local/jamfconnect/SLU.icns" with title "SLU ITS: Password Prompt" giving up after 900)
	    if button returned of currentUserPassword is equal to "OK" then
	        return text returned of currentUserPassword
	    else
	        return "timeout"
	    end if
OOP
	)
	if [[ -z "$currentUserPassword" ]];
	then
	    echo "No password entered"
	    osascript -e "display dialog \"Error! You did not enter a password. Please try again.\" buttons {\"OK\"} default button \"OK\" with icon POSIX file \"/usr/local/jamfconnect/SLU.icns\" with title \"SLU ITS: Password Prompt\""
	    password_Prompt
	elif [[ "$currentUserPassword" == 'timeout' ]];
	then
    	echo "Log: Timed out."
        password_Prompt
    elif [[ "$currentUserPassword" == 'cancel' ]];
    then
    	echo "Log: User canceled in password prompt"
        return 1
	fi
    return 0
}

# Get a list of secure token users to display in check_CurrentUser_Ownership with the $phrase variable
function gather_SecureToken_UserList() {
    secureTokenUserArray=()
    userList=""
    for user in $(ls /Users/);
    do
        username=$(basename "$user")
        if sysadminctl -secureTokenStatus "$username" 2>&1 | grep -q 'ENABLED';
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
function check_CurrentUser_Ownership() {
    currentUserOwner=false
    currentUserGUID=$(dscl . -read /Users/$currentUser GeneratedUID | awk '{print $2}')
    systemVolume=$(diskutil info / | grep "Volume Name" | sed 's/.*: //' | sed 's/^ *//')
    systemVolumePath="/Volumes/$systemVolume"
    for id in $(diskutil apfs listUsers "$systemVolumePath" | grep -E '.*-.*' | awk '{print $2}');
    do
        if [[ "$id" == "$currentUserGUID" ]];
        then
            currentUserOwner=true
        fi
    done
    if [[ "$currentUserOwner" != true ]];
    then
        osascript -e "display dialog \"You are not a volume owner! Your account does not have the proper permission to update.\n\n$phrase\" buttons {\"OK\"} default button \"OK\" with icon POSIX file \"/usr/local/jamfconnect/SLU.icns\" with title \"SLU ITS: OS Update\""
        echo "Log: \"$currentUser\" is not a volume owner, exiting."
        exit 0
    fi
}

function main() {
    if ! icon_Check;
    then
        echo "Log: Exiting for no SLU icon"
        exit 1
    fi
    
    if ! login_Check;
    then
        echo "Log: Exiting for no user logged in"
        exit 1
    fi

    if ! update_Check;
    then
        echo "Log: No updates available"
        exit 0
    fi

    if ! user_Prompt;
    then
        echo "Log: Exiting at first user prompt"
        exit 1
    fi

    if ! prompt_User; # currently doesnt return 1 anywhere
    then
        echo "Log: Exiting at second user prompt"
        exit 1
    fi

    if [[ $(uname -p) == "arm" ]];
    then
        gather_SecureToken_UserList
        check_CurrentUser_Ownership
        if ! password_Prompt;
        then
            echo "Log: Exiting at password prompt"
            exit 1
        fi
        echo "$currentUserPassword" | /usr/sbin/softwareupdate --verbose -iRr --agree-to-license --user "$currentUser" --stdinpass
    else
        /usr/sbin/softwareupdate --verbose -iRr --agree-to-license
    fi

    exit 0
}

main

