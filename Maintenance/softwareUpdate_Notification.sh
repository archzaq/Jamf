#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 1-9-25    ###
### Updated: 1-10-25   ###
### Version: 1.1       ###
##########################

readonly currentUser="$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)"
readonly logPath='/var/log/softwareUpdate.log'
readonly iconPath='/usr/local/jamfconnect/SLU.icns'
readonly dialogTitle='SLU ITS: OS Update'
readonly currentVersion="$(sw_vers --productVersion)"

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

# Tell the user to check for updates
function prompt_User() {
    local userPrompt=$(/usr/bin/osascript <<OOP
    set dialogResult to (display dialog "Check for updates?" buttons {"Cancel", "Check for Updates"} default button "Cancel" with icon POSIX file "$iconPath" with title "$dialogTitle" giving up after 900)
    if button returned of dialogResult is equal to "Check for Updates" then
        return "Check for Updates"
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
    echo "Log: $(date "+%F %T") Dialog for informing the user completed, continuing." | tee -a "$logPath"
    return 0
}

function main() {
    echo "Log: $(date "+%F %T") Beginning Software Update Notification script." | tee "$logPath"

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

    if ! prompt_User;
    then
        echo "Log: $(date "+%F %T") Exiting at user prompt." | tee -a "$logPath"
        exit 1
    fi

    open "x-apple.systempreferences:com.apple.preferences.softwareupdate"

    exit 0
}

main
