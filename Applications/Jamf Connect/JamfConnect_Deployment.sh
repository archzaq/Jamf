#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 7-25-23   ###
### Updated: 3-11-25   ###
### Version: 1.4       ###
##########################

# Locations of Jamf Connect components
readonly launchAgentLocation='/Library/LaunchAgents/com.jamf.connect.plist'
readonly loginImageLocation='/usr/local/jamfconnect/login-background.jpeg'
readonly jamfConnectMenuConfigProfile='/Library/Managed Preferences/com.jamf.connect.plist'
readonly jamfConnectAppLocation='/Applications/Jamf Connect.app'
readonly userAccount="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly defaultIconPath='/usr/local/jamfconnect/SLU.icns'
readonly genericIconPath='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
readonly dialogTitle='SLU ITS: Jamf Connect Install'
readonly logPath='/var/log/JamfConnect_Deployment.log'

# Check for SLU icon file, AppleScript dialog boxes will error without it
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

# Check if someone is logged into the device
function login_Check() {
    case "$userAccount" in
        'root')
            log_Message "\"root\" currently logged in."
            return 1
            ;;
        'loginwindow' | '')
            log_Message "No one logged in."
            return 1
            ;;
        *)
            log_Message "\"$userAccount\" currently logged in."
            return 0
            ;;
    esac
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
            set dialogResult to display dialog promptString buttons {"Cancel", "Continue"} default button "Continue" with icon POSIX file iconPath with title dialogTitle giving up after 900
            set buttonChoice to button returned of dialogResult
            if buttonChoice is equal to "Continue" then
                return buttonChoice
            else
                return "timeout"
            end if
        on error
            return "cancelled"
        end try
OOP
        )
        case "$binDialog" in
            'cancelled')
                log_Message "User selected cancel."
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

# Print the missing components Jamf Connect requires
function individual_Check(){
    log_Message "Missing components:"
    if [ ! -d "$jamfConnectAppLocation" ]; then log_Message " - Jamf Connect application"; fi
    if [ ! -f "$launchAgentLocation" ]; then log_Message " - LaunchAgent"; fi
    if [ ! -f "$loginImageLocation" ]; then log_Message " - login image"; fi
    if [ ! -f "$jamfConnectMenuConfigProfile" ]; then log_Message " - .plist file"; fi
}

# Waits until the Jamf Connect pieces are in place. First waiting for two minutes, retrying after two minutes, then timing out 
function jamfConnect_Check(){
    local counter=0
    local retry=0
    until [ -f "$launchAgentLocation" ] && [ -f "$loginImageLocation" ] && [ -f "$jamfConnectMenuConfigProfile" ] && [ -d "$jamfConnectAppLocation" ];
    do
        sleep 1
        ((counter++))
        if [ $counter -eq 45 ];
        then
            individual_Check
        fi
        if [ $counter -eq 90 ];
        then
            ((retry++))
            if [ $retry -eq 1 ];
            then
                log_Message "Process timed out, retrying."
                counter=0
            elif [ $retry -eq 2 ];
            then
                log_Message "Process timed out twice, attempting Jamf Connect repair."
                /usr/local/bin/jamf policy -event RepairJamfConnect
                counter=0
            elif [ $retry -eq 3 ];
            then
                log_Message "Process timed out three times, exiting."
                return 1
            fi
        fi
    done
    log_Message "All Jamf Connect components installed!"
    return 0
}

# AppleScript - Informing the user of what took place
function inform_Dialog_LogOut() {
    local promptString="$1"
    local count=1
    while [ $count -le 10 ];
    do
        informDialog=$(/usr/bin/osascript <<OOP
        set promptString to "$promptString"
        set iconPath to "$effectiveIconPath"
        set dialogTitle to "$dialogTitle"
        set dialogResult to display dialog promptString buttons {"Log Out"} default button "Log Out" with icon POSIX file iconPath with title dialogTitle giving up after 900
        set buttonChoice to button returned of dialogResult
        if buttonChoice is equal to "Log Out" then
            return buttonChoice
        else
            return "timeout"
        end if
OOP
        )
        case "$informDialog" in
            'timeout')
                log_Message "No response, re-prompting ($count/10)."
                ((count++))
                ;;
            *)
                log_Message "User responded with: $informDialog"
                osascript -e 'tell application "System Events" to log out' &
                log_Message "Sent log out command."
                return 0
                ;;
        esac
    done
    return 1
}

# Append current status to log file
function log_Message() {
    echo "Log: $(date "+%F %T") $1" | tee -a "$logPath"
}

function main(){
    echo "Log: $(date "+%F %T") Beginning Jamf Connect Deployment script." | tee "$logPath"

    if ! icon_Check;
    then
        log_Message "Exiting for no SLU icon."
        exit 1
    fi
    
    if ! login_Check;
    then
        log_Message "Exiting for invalid user logged in."
        exit 1
    fi

    log_Message "Displaying first dialog."
    if ! binary_Dialog "You are about to receive the latest version of Jamf Connect.\n\n\
You will be prompted to log out of your device after the install of Jamf Connect has completed.\n\n\
If you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000.";
    then
        log_Message "Exiting at first dialog."
        exit 0
    fi

    log_Message "Running Jamf Recon."
    /usr/local/bin/jamf recon
    if [ $? -eq 0 ];
    then
        log_Message "Jamf Recon completed."
    else
        log_Message "Jamf Recon failed, trying again in 30 seconds."
        sleep 30
        /usr/local/bin/jamf recon
    fi

    log_Message "Checking for Jamf Application, LaunchAgent, login image, and .plist file." 
    if ! jamfConnect_Check;
    then
        log_Message "Exiting at Jamf Connect check."
        exit 1
    fi

    log_Message "Prompting user to log out"
    if ! inform_Dialog_LogOut "The Jamf Connect installation is complete!\n\n\
Please log out of your Mac; when you log in again, you will be prompted to enter your Okta credentials.\n\n\
If you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000.";
    then
        log_Message "Exiting at log out dialog."
        exit 1
    fi

    log_Message "Exiting!"
    exit 0
}

main

