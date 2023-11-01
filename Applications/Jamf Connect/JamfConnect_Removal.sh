#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

# Check if file paths exist
if [ ! -f /usr/local/bin/authchanger ] || [ ! -f /usr/local/lib/pam/pam_saml.so.2 ] || [ ! -d "/Library/Security/SecurityAgentPlugins/JamfConnectLogin.bundle" ];
then
    echo "One or more required files not found"
fi

# Check if authchanger command exists
if ! command -v /usr/local/bin/authchanger >/dev/null 2>&1;
then
    echo "authchanger command not found"
else
    # Reset authchanger
    sudo /usr/local/bin/authchanger -reset
fi

sleep 2

# Remove files and directories
rm /usr/local/bin/authchanger
rm /usr/local/lib/pam/pam_saml.so.2
rm /Library/LaunchAgents/com.jamf.connect.plist
rm -r "/Library/Security/SecurityAgentPlugins/JamfConnectLogin.bundle"
rm -r "/Applications/Jamf Connect.app"
rm -r "/Library/Application Support/JAMF/Receipts/SLULogos_JamfConnect_5-30-23.pkg"
rm -r "/Library/Application Support/JAMF/Receipts/SLULogos_JamfConnect_5-30-23-Signed.pkg"
rm -r "/Library/Application Support/JAMF/Receipts/JamfConnectLaunchAgent.pkg" 
rm -r "/Library/Application Support/JAMF/Receipts/JamfConnectLaunchAgent2.pkg" 

if pgrep "Jamf Connect" >/dev/null;
then
    pkill "Jamf Connect"
else
    echo "Jamf Connect not running"
fi

exit 0
