#!/bin/bash

# Admin credentials
adminUser=$4
adminPassword=$5

# Window Title
title='MacOS Secure Token'

# Store the logged in user's name to a variable
userName="$(defaults read /Library/Preferences/com.apple.loginwindow lastUserName)"
echo "Last user to login: $userName"

# Check for its_admin account
if ls /Users | grep -q 'its_admin';
then
    echo "its_admin exists. Continuing..."
else
    echo "No its_admin account. Exiting..."
    exit 1
fi

# GUI dialog for the user
osascript -e "display dialog \"Your partners in ITS are working to enhance the security of your Mac. To finish this enhancement, your user password is required. \n\nNote that this password is not collected, nor does it ever leave your computer.\" buttons {\"OK\"} default button \"OK\" with title \"$title\""

# Check if user already has a secure token
if sysadminctl -secureTokenStatus "$userName" 2>&1 | grep -q 'ENABLED';
then
    echo "User $userName already has a secure token"
    osascript -e "display dialog \"You have already been granted a secure token!\" buttons {\"OK\"} default button \"OK\" with title \"$title\""
    exit 0
fi

# Prompt user for their password
echo "Prompting user for their password"
userPassword=$(osascript <<EOF
    set userPassword to (display dialog "Please enter your computer password to be granted a secure token:" with hidden answer default answer "" with title "MacOS Secure Token: Password Prompt" giving up after 90)
    if button returned of userPassword is equal to "OK" then
        return text returned of userPassword
    else
        return "timeout"
    end if
EOF
)

# Handle user input timeout or them selecting Cancel
if [[ "$userPassword" == "timeout" ]];
then
    echo "Timeout error"
    osascript -e "display dialog \"Error! You did not enter your password within the specified time limit.\" buttons {\"OK\"} default button \"OK\" with title \"$title\""
    exit 1
elif [[ "$userPassword" == '' ]];
then
    echo "No password entered"
    osascript -e "display dialog \"Error! You did not enter a password.\" buttons {\"OK\"} default button \"OK\" with title \"$title\""
    exit 1
fi

sleep 3

# Test sysadminctl output
output=$(sudo sysadminctl -adminUser "$adminUser" -adminPassword "$adminPassword" -secureTokenOn "$userName" -password "$userPassword" 2>&1)
   
# Grant secure token
if [[ $output == *"Done"* ]];
then
    echo "Success!!"
    sysadminctl -adminUser "$adminUser" -adminPassword "$adminPassword" -secureTokenOn "$userName" -password "$userPassword"
    osascript -e "display dialog \"You have been successfully granted a secure token!\" buttons {\"OK\"} default button \"OK\" with title \"$title\""
else
    echo "Error with sysadminctl command"
    osascript -e "display dialog \"Error! You have not been granted a secure token. Please try again.\" buttons {\"OK\"} default button \"OK\" with title \"$title\""
    exit 1
fi
