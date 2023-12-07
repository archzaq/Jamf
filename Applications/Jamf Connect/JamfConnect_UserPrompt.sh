#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

# Locations of Jamf Connect components
launch_agent="/Library/LaunchAgents/com.jamf.connect.plist"
login_image="/usr/local/jamfconnect/login-background.jpeg"
jamf_connect_plist="/Library/Managed Preferences/com.jamf.connect.plist"
jamf_connect_app="/Applications/Jamf Connect.app"

# Dialog box to inform user of the overall process taking place
function user_Prompt() {
    userPrompt=$(osascript <<OOP
        set dialogResult to display dialog "Your device is pending the installation of Jamf Connect. Please log out, upon logging back in, the install will begin.\n\nYou have until 12/19 before the installation will be forced.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000." buttons {"Dismiss", "Log Out"} default button "Log Out" with title "SLU ITS: Jamf Connect Install" giving up after 900
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
        sleep 300
        double_Check
    else
    	echo "Log: Dialog box timed out"
    	exit 1
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
