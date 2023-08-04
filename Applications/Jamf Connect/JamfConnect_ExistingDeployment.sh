#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

# Locations of Jamf Connect components
launch_agent="/Library/LaunchAgents/com.jamf.connect.plist"
login_image="/usr/local/jamfconnect/login-background.jpeg"
jamf_connect_plist="/Library/Managed Preferences/com.jamf.connect.plist"
jamf_connect_app="/Applications/Jamf Connect.app"

# Function that waits until the Jamf Connect pieces are in place, retrying after three minutes then timing out after another three
function connect_Check(){
    echo "Awaiting the alignment of various components"
    counter=0
    until [ -f "$launch_agent" ] && [ -f "$login_image" ] && [ -f "$jamf_connect_plist" ] && [ -d "$jamf_connect_app" ];
    do
        sleep 1
        ((counter++))
        if [ $counter == 180 ];
        then
            if [ $retry ];
            then
                echo "Process timed out twice, exiting"
                exit 1
            fi
            echo "Process timed out, retrying"
            retry=true
            connect_Check
        fi
    done
}

# Jamf Recon to force device into proper smart group after the two packages are installed
/usr/local/bin/jamf recon

connect_Check

echo "Components aligned"
echo "Prompting user to restart"

# GUI dialog for the user
macRestart=$(osascript <<OOP
    set dialogResult to display dialog "The Jamf Connect installation is complete!\n\nPlease restart your Mac; when you log in again, you will be prompted to enter your Okta credentials.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000." buttons {"Restart", "Cancel"} default button "Restart" with title "SLU ITS: Restart" giving up after 300
    if button returned of dialogResult is equal to "Restart" then
        return "User selected: Restart"
    else
        return "Dialog timed out"
    end if
OOP
)

echo $macRestart

if [[ $macRestart == *"Restart"* ]];
then
    /usr/local/bin/authchanger -reset -JamfConnect
    
    sleep 1
    
    osascript -e 'tell app "System Events" to restart' &
    echo "Sent restart command"
    exit 0
else
    /usr/local/bin/authchanger -reset -JamfConnect
    exit 0
fi
