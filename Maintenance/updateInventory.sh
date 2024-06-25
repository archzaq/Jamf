#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 7-12-23   ###
### Updated: 6-25-24   ###
### Version: 1.4       ###
##########################

readonly jamf_connect_plist="/Library/Managed Preferences/com.jamf.connect.plist"
readonly jamf_connect_app="/Applications/Jamf Connect.app"
readonly currentName=$(hostname)
readonly logPath='/var/log/softwareUpdate.log'

# Often there is a jamf action already running in the background after enrollment.
# This is an attempt at handling that
function check_already_running() {
    local check_result="$1"
    local event="$2"

    if [[ $checkCount > 10 ]];
    then
        checkCount=0
        return 1
    fi

    if [[ $check_result == *"already being run"* ]];
    then
    	echo "$check_result"
        echo "Log: $(date) Policy already being run, retrying in 30 seconds..." | tee -a "$logPath"
        ((checkCount++))
        sleep 30
        if [[ ! -z "$event" ]];
        then
            check_result=$(/usr/local/bin/jamf policy -event "$event")
            check_already_running "$check_result" "$event"
        else
            check_result=$(/usr/local/bin/jamf policy)
            check_already_running "$check_result"
        fi
    fi
}

function check_Name() {
    # If the current device name contains "Mac" return false
    if [[ $currentName == *"Mac"* ]];
    then
        return 1

    # If the current device name already contains two hyphens return true
    elif [[ $currentName == *-*-* ]];
    then
        return 0

    # If the current device name already contains a hyphen return true
    elif [[ $currentName == *"-"* ]];
    then
        return 0

    # If the current device name fails to match any conditions return false
    else
        return 1
    fi
}

checkCount=0
echo "Log: $(date) Checking for lingering enrollment policies..." | tee "$logPath"
enrollment_check_result=$(/usr/local/bin/jamf policy -event enrollmentComplete)
if ! check_already_running "$enrollment_check_result" "enrollmentComplete";
then
    echo "Log: $(date) Checked more than 10 times" | tee -a "$logPath"
fi
echo "Log: $(date) Enrollment policy check complete, continuing..." | tee -a "$logPath"

sleep 1

echo "Log: $(date) Checking for correct naming" | tee -a "$logPath"
if ! check_Name;
then
    echo "Log: $(date) Device name is \"$currentName\", renaming" | tee -a "$logPath"
    /usr/local/bin/jamf policy -event rename
else
    echo "Log: $(date) Device name, \"$currentName\" fits naming scheme" | tee -a "$logPath"
fi
echo "Log: $(date) Name check complete, continuing..." | tee -a "$logPath"

sleep 1

checkCount=0
echo "Log: $(date) Checking for remaining policies..." | tee -a "$logPath"
policy_check_result=$(/usr/local/bin/jamf policy)
if ! check_already_running "$policy_check_result";
then
    echo "Log: $(date) Checked more than 10 times" | tee -a "$logPath"
fi
echo "Log: $(date) Standard policy check complete, continuing..." | tee -a "$logPath"

sleep 1

echo "Log: $(date) Updating inventory..." | tee -a "$logPath"
/usr/local/bin/jamf recon
echo "Log: $(date) Inventory update complete, checking for Rosetta and Jamf Connect" | tee -a "$logPath"

if [[ $(/usr/bin/uname -p) = 'arm' ]] && [[ ! -f /Library/Apple/usr/libexec/oah/libRosettaRuntime ]];
then
    echo "Log: $(date) Rosetta runtime not present, installing Rosetta" | tee -a "$logPath"
    /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    sleep 1
    echo "Log: $(date) Checking for other missing enrollment policies" | tee -a "$logPath"
    /usr/local/bin/jamf policy -event enrollmentComplete
    if [ ! -f /Library/Apple/usr/libexec/oah/libRosettaRuntime ];
    then
        echo "Log: $(date) Rosetta runtime still not present, trying install again" | tee -a "$logPath"
    	/usr/sbin/softwareupdate --install-rosetta --agree-to-license
    fi
elif [[ $(/usr/bin/uname -p) = 'arm' ]];
then
    echo "Log: $(date) Rosetta runtime present" | tee -a "$logPath"
fi

if [[ ! -d "$jamf_connect_app" ]] || [[ ! -f "$jamf_connect_plist" ]];
then
    echo "Log: $(date) Missing Jamf Connect, installing" | tee -a "$logPath"
    /usr/local/bin/jamf policy -event MissingJamfConnect
else
    echo "Log: $(date) Jamf Connect already installed" | tee -a "$logPath"
fi

echo "Log: $(date) Exiting!" | tee -a "$logPath"
exit 0
