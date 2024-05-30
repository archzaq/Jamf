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
        set dialogResult to display dialog "You are about to receive the latest version of Jamf Connect.\n\nYou will be prompted to restart your device after the install of Jamf Connect has completed.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000." buttons {"Continue"} default button "Continue" with title "SLU ITS: Jamf Connect Install" giving up after 900
        if button returned of dialogResult is equal to "Continue" then
            return "User selected: Continue"
        else
            return "Dialog timed out"
        end if
OOP
    )
    userAnswer=$(echo "$userPrompt")
    if [[ "$userAnswer" == *"Continue"* ]];
    then
        echo "Log: User selected \"Continue\" through the first dialog box"
    else
        echo "Log: Reprompting user with the first dialog box"
        user_Prompt
    fi
}

# Waits until the Jamf Connect pieces are in place, retrying after three minutes then timing out after another three
function connect_Check(){
    counter=0
    retry=0
    repair_trigger=0
    echo "Log: Checking for components"
    until [ -f "$launch_agent" ] && [ -f "$login_image" ] && [ -f "$jamf_connect_plist" ] && [ -d "$jamf_connect_app" ];
    do
        sleep 1
        ((counter++))
        if [ $counter -eq 180 ];
        then
            ((retry++))
            if [ $retry -eq 2 ];
            then
                echo "Log: Process timed out twice, attempting to repair install.."
                /usr/local/bin/jamf recon
                repair_trigger=1
                sleep 30
            elif [ $retry -eq 3 ];
            then
                echo "Log: Process timed out three times, exiting..."
                exit 1
            fi

            if [ $repair_trigger -eq 0 ];
            then
                echo "Log: Process timed out, retrying"
            fi
        fi
    done
}

# Dialog box to prompt the user to restart
function device_Restart(){
    macRestart=$(osascript <<OOP
        set dialogResult to display dialog "The Jamf Connect installation is complete!\n\nPlease restart your Mac; when you log in again, you will be prompted to enter your Okta credentials.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000." buttons {"Restart"} default button "Restart" with title "SLU ITS: Restart" giving up after 900
        if button returned of dialogResult is equal to "Restart" then
            return "User selected: Restart"
        else
            return "Dialog timed out"
        end if
OOP
    )
    /usr/local/bin/authchanger -reset -JamfConnect
    sleep 1
    macRestartAnswer=$(echo "$macRestart")
    if [[ $macRestartAnswer == *"Restart"* ]];
    then
        echo "Log: User selected \"Restart\". Sending restart command"
        echo "Log: Sent restart command"
        osascript -e 'tell application "System Events" to restart'
        exit 0
    else
        exit 0
    fi
}

function main(){
    echo "Log: Informing user of the Jamf Connect installation"
    user_Prompt

    echo "Log: Running recon"
    /usr/local/bin/jamf recon

    echo "Log: Awaiting the alignment of various components"
    connect_Check
    echo "Log: Components aligned"

    echo "Log: Prompting user to restart"
    device_Restart
}

main
