#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

updateCount=0
currentUser="$(defaults read /Library/Preferences/com.apple.loginwindow lastUserName)"

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
    set dialogResult to (display dialog "$promptMessage" buttons {"Cancel", "Begin Download and Install"} default button "Cancel" with icon POSIX file "/usr/local/jamfconnect/SLU.icns" with title "SLU ITS: OS Update" giving up after 900)
    if button returned of dialogResult is equal to "Begin Download and Install" then
        return "Begin Download and Install"
    else
        return "timeout"
    end if
OOP
    )
    if [ -z "$userPrompt" ];
    then
        echo "Log: User selected cancel"
        exit 0
    elif [[ "$userPrompt" == "timeout" ]];
    then
        echo "Log: Timed out. Reprompting."
        prompt_User
    fi
}

# Prompt the user for their password, reprompting if they enter nothing or the dialog times out
function password_Prompt(){
	echo "Prompting user for their password"
	currentUserPassword=$(osascript <<OOP
	    set currentUserPassword to (display dialog "Please enter your computer password to continue with OS update:" buttons {"Cancel", "OK"} default button "OK" with hidden answer default answer "" with icon POSIX file "/usr/local/jamfconnect/SLU.icns" with title "SLU ITS: Password Prompt" giving up after 900)
	    if button returned of currentUserPassword is equal to "OK" then
	        return text returned of currentUserPassword
	    else
	        return "timeout"
	    end if
OOP
	)
    if [[ $? != 0 ]];
    then
        echo "Log: User selected cancel"
        exit 0
	elif [[ -z "$currentUserPassword" ]];
	then
	    echo "No password entered"
	    osascript -e "display dialog \"Error! You did not enter a password. Please try again.\" buttons {\"OK\"} default button \"OK\" with icon POSIX file \"/usr/local/jamfconnect/SLU.icns\" with title \"SLU ITS: Password Prompt\""
	    password_Prompt
	elif [[ "$currentUserPassword" == 'timeout' ]];
	then
    	echo "Log: Timed out, exiting..."
		exit 0
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
        exit 0
    fi
}

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

function main() {
    if [[ ! -f "/usr/local/jamfconnect/SLU.icns" ]];
    then
        /usr/local/bin/jamf policy
        if [[ ! -f "/usr/local/jamfconnect/SLU.icns" ]];
        then
        	echo "Log: No SLU icon installed, exiting."
            exit 1
        fi
    fi

    result=$(/usr/sbin/softwareupdate -l)
    echo "Available updates:"
    echo "$result"

    macOSAvailableUpgrades=$(echo "$result" | grep "Label: macOS")
    if [[ "$macOSAvailableUpgrades" == '' ]];
    then
        echo "Log: No updates available."
	    osascript -e "display dialog \"Your device is fully up to date! Thank you.\" buttons {\"OK\"} default button \"OK\" with icon POSIX file \"/usr/local/jamfconnect/SLU.icns\" with title \"SLU ITS: OS Update\""
        exit 0
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

    prompt_User

    if [ $(uname -p) = "arm" ];
    then
        gather_SecureToken_UserList
        check_CurrentUser_Ownership
        password_Prompt
        echo "$currentUserPassword" | /usr/sbin/softwareupdate --verbose -iRr --agree-to-license --user "$currentUser" --stdinpass
    else
        /usr/sbin/softwareupdate --verbose -iRr --agree-to-license
    fi
}

main
