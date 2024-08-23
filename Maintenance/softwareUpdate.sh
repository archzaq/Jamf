#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 1-23-24   ###
### Updated: 8-23-24   ###
### Version: 1.15      ###
##########################

managementAccount="$4"
managementAccountPass="$5"
passwordPromptBool=false
readonly currentUser="$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)"
readonly logPath='/var/log/softwareUpdate.log'
readonly iconPath='/usr/local/jamfconnect/SLU.icns'
readonly dialogTitle='SLU ITS: OS Update'

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

# Check for any OS updates and store them in $availableUpgrades
# Also counts how many updates available
function update_Check() {
    updateCount=0
    local result=$(/usr/sbin/softwareupdate -l)
    echo "Log: $(date "+%F %T") Available updates:" | tee -a "$logPath"
    echo "Log: $(date "+%F %T") $result" | tee -a "$logPath"

    # WIP
    local availableUpgrades=$(echo "$result" | grep "Label: ")
    if [[ "$availableUpgrades" == '' ]];
    then
        return 1
    fi
    cleanUpdateList=$(echo "$availableUpgrades" | awk '{print $3,$4,$5}')
    echo "Log: $(date "+%F %T") Available updates:" | tee -a "$logPath"
    echo "Log: $(date "+%F %T") $cleanUpdateList" | tee -a "$logPath"
    
    # Loop through each line of $availableUpgrades
    while IFS= read -r line;
    do
        updateCount=$((updateCount + 1))
    done <<< "$availableUpgrades"
    echo "Log: $(date "+%F %T") Total macOS updates available: $updateCount" | tee -a "$logPath"
    return 0
}

# Inform the user of how many updates they currently have with $cleanUpdateList
function prompt_User() {
    local promptMessage=""
    if ((updateCount > 1));
    then
        promptMessage="You have more than one OS update available, you will need to run this policy for each available update.\n\nAvailable Updates:\n$cleanUpdateList\n\nYour device will restart when the download is complete. Save all of your files before proceeding.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000."
    elif ((updateCount == 1));
    then
        promptMessage="You have one OS update available.\n\nAvailable Update:\n$cleanUpdateList\n\nYour device will restart when the download is complete. Save all of your files before proceeding.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000."
    fi
    local userPrompt=$(/usr/bin/osascript <<OOP
    set dialogResult to (display dialog "$promptMessage" buttons {"Cancel", "Begin Download and Install"} default button "Cancel" with icon POSIX file "$iconPath" with title "$dialogTitle" giving up after 900)
    if button returned of dialogResult is equal to "Begin Download and Install" then
        return "Begin Download and Install"
    else
        return "timeout"
    end if
OOP
    )
    if [ -z "$userPrompt" ];
    then
        echo "Log: $(date "+%F %T") User selected cancel." | tee -a "$logPath"
        return 1
    elif [[ "$userPrompt" == "timeout" ]];
    then
        echo "Log: $(date "+%F %T") Timed out. Reprompting." | tee -a "$logPath"
        prompt_User
    fi
    echo "Log: $(date "+%F %T") Dialog for available updates completed, continuing." | tee -a "$logPath"
    return 0
}

# Prompt the user for their password, reprompting if they enter nothing
function password_Prompt(){
    local readonly passwordTitle='SLU ITS: Password Prompt'
    echo "Log: $(date "+%F %T") Prompting user for their password." | tee -a "$logPath"
    currentUserPassword=$(/usr/bin/osascript <<OOP
        set currentUserPassword to (display dialog "Please enter your computer password to continue with OS update:" buttons {"Cancel", "OK"} default button "OK" with hidden answer default answer "" with icon POSIX file "$iconPath" with title "$passwordTitle" giving up after 900)
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
        password_Prompt
    elif [[ "$currentUserPassword" == 'timeout' ]];
    then
        echo "Log: $(date "+%F %T") Timed out." | tee -a "$logPath"
        password_Prompt
    fi
    echo "Log: $(date "+%F %T") Password prompt finished." | tee -a "$logPath"
    passwordPromptBool=true
    return 0
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

# Dialog box to inform user the update is installing
function update_Prompt() {
    local updatePrompt=$(/usr/bin/osascript <<OOP
    set updatePrompt to (display dialog "Your device is downloading the update in the background!\n\nOnce the download is finished, your device will automatically restart to apply the changes. If you don't see any updates after an hour, please try restarting your device and running this policy again.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000." buttons {"OK"} default button "OK" with icon POSIX file "$iconPath" with title "$dialogTitle" giving up after 900)
    if button returned of updatePrompt is equal to "OK" then
        return "OK"
    else
        return "timeout"
    end if
OOP
    )
    if [[ "$updatePrompt" == 'OK' ]];
    then
        echo "Log: $(date "+%F %T") User selected \"OK\" through the final dialog box." | tee -a "$logPath"
        /usr/bin/osascript -e 'tell application "Terminal" to do script "caffeinate -d"'
    fi
}

function main() {
    echo "Log: $(date "+%F %T") Beginning Software Update script." | tee "$logPath"

    if ! icon_Check;
    then
        echo "Log: $(date "+%F %T") Exiting for no SLU icon." | tee -a "$logPath"
        exit 1
    fi
    
    if ! login_Check;
    then
        echo "Log: $(date "+%F %T") Exiting for invalid user logged in." | tee -a "$logPath"
        exit 1
    fi

    if ! update_Check;
    then
        echo "Log: $(date "+%F %T") No updates available." | tee -a "$logPath"
        /usr/bin/osascript -e "display dialog \"Your device's OS is fully up to date! Thank you.\" buttons {\"OK\"} default button \"OK\" with icon POSIX file \"$iconPath\" with title \"$dialogTitle\""
        exit 0
    fi

    if ! prompt_User;
    then
        echo "Log: $(date "+%F %T") Exiting at user prompt." | tee -a "$logPath"
        exit 1
    fi

    # To upgrade on Apple Silicon, the user needs to have a secure token and they will be prompted for their password.
    # If they do not have a secure token, it will check for our management account to exist with the proper permissions.
    # If that exists, it will use the management account to grant the user a secure token.
    if [[ $(/usr/bin/uname -p) == 'arm' ]];
    then
        if ! check_Ownership "$currentUser";
        then
            echo "Log: $(date "+%F %T") Attempting to assign secure token to \"$currentUser\" using the management account." | tee -a "$logPath"
            if ! account_Check "$managementAccount";
            then
                echo "Log: $(date "+%F %T") Management account does not exist, exiting." | tee -a "$logPath"
                /usr/bin/osascript -e 'display alert "An error has occurred" message "Management account does not exist. Unable to grant the proper permission to continue with the update." as critical buttons {"OK"} default button "OK" giving up after 900'
                exit 1
            fi

            if ! admin_Check "$managementAccount";
            then
                echo "Log: $(date "+%F %T") Management account not an admin, exiting." | tee -a "$logPath"
                /usr/bin/osascript -e 'display alert "An error has occurred" message "Management account is not an admin. Unable to grant the proper permission to continue with the update." as critical buttons {"OK"} default button "OK" giving up after 900'
                exit 1
            fi
            
            if ! check_Ownership "$managementAccount";
            then
                echo "Log: $(date "+%F %T") Management account does not have volume ownership, exiting." | tee -a "$logPath"
                /usr/bin/osascript -e 'display alert "An error has occurred" message "Management account does not have volume ownership. Unable to assign secure token." as critical buttons {"OK"} default button "OK" giving up after 900'
                exit 1
            fi

            if ! password_Prompt;
            then
                echo "Log: $(date "+%F %T") Exiting at password prompt." | tee -a "$logPath"
                exit 1
            fi

            if ! assign_Token;
            then
                echo "Log: $(date "+%F %T") Management account unable to grant a secure token, exiting." | tee -a "$logPath"
                /usr/bin/osascript -e 'display alert "An error has occurred" message "Unable to assign secure token. Issue with sysadminctl command." as critical buttons {"OK"} default button "OK" giving up after 900'
                exit 1
            fi
        fi

        if [ "$passwordPromptBool" = true ];
        then
            echo "Log: $(date "+%F %T") Already asked for password, continuing." | tee -a "$logPath"
        else
            if ! password_Prompt;
            then
                echo "Log: $(date "+%F %T") Exiting at password prompt." | tee -a "$logPath"
                exit 1
            fi
        fi

        update_Prompt
        echo "Log: $(date "+%F %T") Beginning download of update." | tee -a "$logPath"
        /usr/sbin/softwareupdate -i -a --restart --agree-to-license --verbose --user "$currentUser" --stdinpass "$currentUserPassword"

    # Intel device upgrade path
    else
        update_Prompt
        echo "Log: $(date "+%F %T") Beginning download of update." | tee -a "$logPath"
        /usr/sbin/softwareupdate -i -a --restart --agree-to-license --verbose
    fi

    exit 0
}

main

