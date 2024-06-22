#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 7-25-23   ###
### Updated: 6-21-24   ###
### Version: 1.6       ###
##########################

# Locations of Jamf Connect components
readonly launch_agent="/Library/LaunchAgents/com.jamf.connect.plist"
readonly login_image="/usr/local/jamfconnect/login-background.jpeg"
readonly jamf_connect_plist="/Library/Managed Preferences/com.jamf.connect.plist"
readonly jamf_connect_app="/Applications/Jamf Connect.app"
readonly lock_file="/var/run/jamf_connect_install.lock"
promptCount=0 

# Dialog box to inform user of the overall process taking place
function user_Prompt() {
    userPrompt=$(osascript <<OOP
        set dialogResult to display dialog "You are about to receive the latest version of Jamf Connect.\n\nYou will be prompted to log out of your device after the install of Jamf Connect has completed.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000." buttons {"Continue"} default button "Continue" with title "SLU ITS: Jamf Connect Install" giving up after 900
        if button returned of dialogResult is equal to "Continue" then
            return "User selected: Continue"
        else
            return "Dialog timed out"
        end if
OOP
    )
    userAnswer=$(echo "$userPrompt")
    ((promptCount++))
    if [[ "$userAnswer" == *"Continue"* ]];
    then
        echo "Log: User selected \"Continue\" through the first dialog box"
    elif [ "$promptCount" -le 10 ];
    then
        echo "Log: Reprompting user with the first dialog box"
        user_Prompt
    else
        echo "Log: User prompted 10 times, exiting..."
        exit 1
    fi
}

# Allow the user to delay the install as they will need to log out upon its completion
function logOut_Prompt() {
    logOutPrompt=$(osascript <<OOP
        set dialogResult to display dialog "After the install has completed, you will need to log out of your device for the changes to take effect. \n\nIf you are still working, select \"Dismiss\". This dialog box will return in five minutes. If you need more time, select \"Dismiss\" again.\n\nOnce you are ready to begin, select \"Continue\"." buttons {"Continue", "Dismiss"} default button "Continue" with title "SLU ITS: Jamf Connect Install" giving up after 900
        if button returned of dialogResult is equal to "Continue" then
            return "User selected: Continue"
        else
            return dialogResult
        end if
OOP
    )
    logOutAnswer=$(echo "$logOutPrompt")
    if [[ "$logOutAnswer" == *"Continue"* ]];
    then
        echo "Log: User selected \"Continue\" to begin the installation of Jamf Connect and allow a log out"
    elif [[ "$logOutAnswer" == *"Dismiss"* ]];
    then
        echo "Log: User selected \"Dismiss\". Prompting again in five minutes"
        sleep 300
        logOut_Prompt
    else
        logOut_Prompt
    fi
}

# Waits until the Jamf Connect pieces are in place, retrying after three minutes then timing out after another three
function connect_Check(){
    counter=0
    repair_trigger=0
    retry=0
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

# Dialog box to prompt the user to log out 
function device_LogOut(){
    macLogOut=$(osascript <<OOP
        set dialogResult to display dialog "The Jamf Connect installation is complete!\n\nPlease log out of your Mac; when you log in again, you will be prompted to enter your Okta credentials.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000." buttons {"Log Out"} default button "Log Out" with title "SLU ITS: Log Out" giving up after 900
        if button returned of dialogResult is equal to "Log Out" then
            return "User selected: Log Out"
        else
            return "Dialog timed out"
        end if
OOP
    )
    /usr/local/bin/authchanger -reset -JamfConnect
    sleep 1
    macLogOutAnswer=$(echo "$macLogOut")
    if [[ $macLogOutAnswer == *"Log Out"* ]];
    then
        echo "Log: User selected \"Log Out\". Sending log out command"
        osascript -e 'tell application "System Events" to log out' &
        echo "Log: Sent log out command"
        exit 0
    else
        osascript -e 'tell application "System Events" to log out' &
        exit 0
    fi
}


# runs the thang
function main(){
    if [ ! -f "$lock_file" ];
    then
        /usr/bin/touch "$lock_file"
        trap 'rm -f "$lock_file"' EXIT

        echo "Log: Informing user of the Jamf Connect installation"
        user_Prompt
        
        echo "Log: Asking the user if they are able to restart or if they want to delay the install"
        logOut_Prompt

        echo "Log: Running recon"
        /usr/local/bin/jamf recon
        echo "Log: Recon complete"

        echo "Log: Awaiting the alignment of various components"
        connect_Check
        echo "Log: Components aligned"

        echo "Log: Prompting user to restart"
        device_LogOut
    else
        echo "Log: Lock file exists. Policy is already running"
        exit 0
    fi
}

main

