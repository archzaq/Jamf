#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

title='SLU ITS: MacOS Secure Token'
adminUser=$4
adminPassword=$5
userName="$(defaults read /Library/Preferences/com.apple.loginwindow lastUserName)"
echo "Last user to login: $userName"

function password_Prompt(){
    userPassword=$(osascript <<EOF
        set userPassword to (display dialog "Please enter your computer password to be granted a secure token:" buttons {"OK"} default button "OK" with hidden answer default answer "" with title "SLU ITS: MacOS Secure Token - Password Prompt" giving up after 900)
        if button returned of userPassword is equal to "OK" then
            return text returned of userPassword
        else
            return "timeout"
        end if
EOF
    )
    if [[ "$userPassword" == '' ]];
    then
        echo "No password entered"
        osascript -e "display dialog \"Error! You did not enter a password. Please try again.\" buttons {\"OK\"} default button \"OK\" with title \"SLU ITS: MacOS Secure Token - Password Prompt\""
        password_Prompt
    elif [[ "$userPassword" == 'timeout' ]];
    then
        echo "Timed out"
        osascript -e "display dialog \"Error! You did not enter your password within the specified time limit.\" buttons {\"OK\"} default button \"OK\" with title \"$title\""
        password_Prompt
    fi
}

# Check for its_admin account
if ls /Users | grep -q 'its_admin';
then
    echo "its_admin exists. Continuing..."
else
    echo "No its_admin account. Exiting..."
    exit 1
fi

# Check if user already has a secure token
if sysadminctl -secureTokenStatus "$userName" 2>&1 | grep -q 'ENABLED';
then
    echo "User \"$userName\" already has a secure token"
    exit 0
fi

# GUI dialog for the user
osascript -e "display dialog \"Your partners in ITS are working to enhance the security of your Mac. To finish this enhancement, your user password is required.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000.\" buttons {\"OK\"} default button \"OK\" with title \"$title\""

password_Prompt

sleep 3

# Test sysadminctl output
output=$(sudo sysadminctl -adminUser "$adminUser" -adminPassword "$adminPassword" -secureTokenOn "$userName" -password "$userPassword" -test 2>&1)
   
# Grant secure token
if [[ $output == *"Done"* ]];
then
    echo "Success!!"
    sysadminctl -adminUser "$adminUser" -adminPassword "$adminPassword" -secureTokenOn "$userName" -password "$userPassword"
    osascript -e "display dialog \"You have been successfully granted a secure token!\" buttons {\"OK\"} default button \"OK\" with title \"$title\""
    exit 0
else
    echo "Error with sysadminctl command"
    osascript -e "display dialog \"Error! You have not been granted a secure token. Please try again.\" buttons {\"OK\"} default button \"OK\" with title \"$title\""
    exit 1
fi
