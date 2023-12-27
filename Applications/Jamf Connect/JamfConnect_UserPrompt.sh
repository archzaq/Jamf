#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

# Locations of Jamf Connect components
readonly launch_agent="/Library/LaunchAgents/com.jamf.connect.plist"
readonly login_image="/usr/local/jamfconnect/login-background.jpeg"
readonly jamf_connect_plist="/Library/Managed Preferences/com.jamf.connect.plist"
readonly jamf_connect_app="/Applications/Jamf Connect.app"

# Dialog box to inform user of the overall process taking place
function user_Prompt() {
    userPrompt=$(osascript <<OOP
        set dialogResult to display dialog "Jamf Connect is awaiting installation on your device. Please save your work and log out. Upon logging back into your machine, the installation will begin.\n\nIf you have not initiated this process by 12/19, the installation will begin automatically.\n\nFor any questions, feel free to contact the IT Service Desk at 314-977-4000." buttons {"Dismiss", "Log Out"} default button "Log Out" with title "SLU ITS: Jamf Connect" with icon caution giving up after 900
        return dialogResult
OOP
    )
    userAnswer=$(echo "$userPrompt")
    if [[ "$userAnswer" == *"Log Out"* ]];
    then
        echo "Log: User selected \"Log Out\""
        osascript -e 'tell application "System Events" to log out'
        exit 0
    elif [[ "$userAnswer" == *"Dismiss"* ]];
    then
        echo "Log: User selected \"Dismiss\""
        osascript -e 'display notification "Jamf Connect is awaiting installation on your device. Please save your work and log out." with title "SLU ITS: Jamf Connect"'
        sleep 300
        double_Check
    else
        echo "Log: Dialog box timed out"
        double_Check
    fi
}

function double_Check(){
    echo "Log: Checking for Jamf Connect"
    if [ -f "$launch_agent" ] && [ -f "$login_image" ] && [ -f "$jamf_connect_plist" ] && [ -d "$jamf_connect_app" ];
    then
        echo "Log: All components installed, exiting..."
        exit 0
    else
        echo "Log: Still missing components"
        user_Prompt
    fi
}

user_Prompt
