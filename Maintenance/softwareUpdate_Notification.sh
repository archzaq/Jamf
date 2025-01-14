#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 1-9-25    ###
### Updated: 1-14-25   ###
### Version: 1.5       ###
##########################

readonly currentUser="$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow lastUserName)"
readonly logPath='/var/log/softwareUpdate_Notification.log'
readonly iconPath='/usr/local/jamfconnect/SLU.icns'
readonly dialogTitle='SLU ITS: OS Update'
readonly currentVersion="$(sw_vers --productVersion)"
readonly majorVersion="${currentVersion%%.*}"

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

# Call endoflife.date API to get latest macOS versions
function latest_macOS_Version() {
    local apiJSON="$(curl --request GET \
        --url https://endoflife.date/api/macOS.json \
        --header 'Accept: application/json')"
    
    latestVersion=$(echo "$apiJSON" | jq -r ".[] | select(.cycle==\"$majorVersion\") | .latest")
    
    # Compare versions
    if [[ "$(printf '%s\n' "$currentVersion" "$latestVersion" | sort -V | head -n1)" == "$currentVersion" && "$currentVersion" != "$latestVersion" ]];
    then
        echo "Log: $(date "+%F %T") Update needed: Current version ($currentVersion) is older than latest version ($latestVersion)." | tee -a "$logPath"
        return 0
    else
        echo "Log: $(date "+%F %T") No update needed: Current version ($currentVersion) is up to date." | tee -a "$logPath"
        return 1
    fi
}

# Choose corresponding prompt phrase for each OS version, still WIP
function phrase_Choice() {
    if [[ $majorVersion == 15 ]];
    then
        phrase="Your Mac is running an outdated version of macOS and requires an immediate update.\n\nCurrent macOS Version: $currentVersion\n\nLatest macOS Version: $latestVersion"
    elif [[ $majorVersion == 14 ]] || [[ $majorVersion == 13 ]];
    then
        phrase="Your Mac is running an outdated version of macOS and requires an immediate update.\n\nCurrent macOS Version: $currentVersion\n\nLatest macOS Version: $latestVersion\n\nIf available, please update to the latest major macOS version allowed by your device."
    elif [[ $majorVersion == 12 ]];
    then
        phrase="Your Mac is running an unsupported version of macOS and requires an immediate update.\n\nCurrent macOS Version: $currentVersion\n\nLatest macOS Version: $latestVersion\n\nIf available, please update to the latest major macOS version allowed by your device."
    else
        phrase="Your Mac is running an unsupported version of macOS and requires an immediate update.\n\nCurrent macOS Version: $currentVersion\n\nLatest macOS Version: $latestVersion\n\nIf available, please update to the latest major macOS version allowed by your device."
    fi
    
    echo "Log: $(date "+%F %T") Dialog phrase chosen for macOS $majorVersion." | tee -a "$logPath"
}

# Tell the user to check for updates
function prompt_User() {
    local retries=1
    local MAX_RETRIES=30
    phrase_Choice
    while [[ $retries -le $MAX_RETRIES ]];
    do
        local userPrompt=$(/usr/bin/osascript <<OOP
            set dialogResult to (display dialog "$phrase" buttons {"Cancel", "Check for Updates"} default button "Cancel" with icon POSIX file "$iconPath" with title "$dialogTitle" giving up after 900)
            if button returned of dialogResult is equal to "Check for Updates" then
                return "Check for Updates"
            else
                return "timeout"
            end if
OOP
        )
        if [[ -z "$userPrompt" ]];
        then
            echo "Log: $(date "+%F %T") User selected cancel." | tee -a "$logPath"
            return 1
        elif [[ "$userPrompt" == "timeout" ]];
        then
            echo "Log: $(date "+%F %T") Timed out, reprompting ($retries/$MAX_RETRIES)." | tee -a "$logPath"
            ((retries++))
        else
            echo "Log: $(date "+%F %T") Dialog for informing the user completed, continuing." | tee -a "$logPath"
            return 0
        fi
    done

    echo "Log: $(date "+%F %T") Time out maximum reached." | tee -a "$logPath"
    return 1
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

    if ! latest_macOS_Version;
    then
        echo "Log: $(date "+%F %T") Exiting for no updates available." | tee -a "$logPath"
        exit 1
    fi

    if ! prompt_User;
    then
        echo "Log: $(date "+%F %T") Exiting at user prompt." | tee -a "$logPath"
        exit 1
    fi

    echo "Log: $(date "+%F %T") Opening Software Update in System Settings/Preferences." | tee -a "$logPath"
    open "x-apple.systempreferences:com.apple.preferences.softwareupdate"

    echo "Log: $(date "+%F %T") Exiting successfully." | tee -a "$logPath"
    exit 0
}

main

