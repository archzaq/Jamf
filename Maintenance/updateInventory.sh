#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 07-12-23  ###
### Updated: 05-05-24  ###
### Version: 2.0       ###
##########################

readonly jamf_connect_plist="/Library/Managed Preferences/com.jamf.connect.plist"
readonly jamf_connect_app="/Applications/Jamf Connect.app"
readonly logPath='/var/log/updateInventory.log'

# Attempt to handle a jamf policy already being run
function check_already_running() {
    local checkResult="$1"
    local event="$2"
    local maxAttempts=10
    local attempt=0

    while [[ $attempt -lt $maxAttempts ]];
    do
        if [[ $checkResult == *"already being run"* ]];
        then
            echo "Log: $(date "+%F %T") Policy already being run, retrying in 30 seconds (Attempt $((attempt+1)))" | tee -a "$logPath"
            sleep 30
            ((attempt++))
            if [[ ! -z "$event" ]];
            then
                checkResult=$(/usr/local/bin/jamf policy -event "$event")
            else
                checkResult=$(/usr/local/bin/jamf policy)
            fi
        else
            return 0
        fi
    done

    return 1
}

# Return false if the current device name doesnt fit naming scheme
function check_Name() {
    currentName=$(hostname)

    # If the current device name contains "Mac" or "SLU" return false
    if [[ "$currentName" == *"Mac"* ]] || [[ "$currentName" == "SLU-"* ]];
    then
        return 1

    # If the current device name already contains two hyphens return true
    elif [[ "$currentName" == *-*-* ]];
    then
        return 0

    # If the current device name already contains a hyphen return true
    elif [[ "$currentName" == *"-"* ]];
    then
        return 0

    # If the current device name fails to match any conditions return false
    else
        return 1
    fi
}

/usr/bin/caffeinate -d &
CAFFEINATE_PID=$!
trap "kill $CAFFEINATE_PID" EXIT

# Enrollment policies
echo "Log: $(date "+%F %T") Checking for lingering enrollment policies" | tee "$logPath"

enrollment_check_result=$(/usr/local/bin/jamf policy -event enrollmentComplete)
if ! check_already_running "$enrollment_check_result" "enrollmentComplete";
then
    echo "Log: $(date "+%F %T") Checked $maxAttempts times, giving up" | tee -a "$logPath"
else
    echo "Log: $(date "+%F %T") Enrollment policy check complete" | tee -a "$logPath"
fi



sleep 1



# General policies
echo "Log: $(date "+%F %T") Checking for remaining policies" | tee -a "$logPath"

policy_check_result=$(/usr/local/bin/jamf policy)
if ! check_already_running "$policy_check_result";
then
    echo "Log: $(date "+%F %T") Checked $maxAttempts times, giving up" | tee -a "$logPath"
else
    echo "Log: $(date "+%F %T") Standard policy check complete" | tee -a "$logPath"
fi



sleep 1



# Update inventory
echo "Log: $(date "+%F %T") Updating inventory" | tee -a "$logPath"
/usr/local/bin/jamf recon
echo "Log: $(date "+%F %T") Inventory update complete" | tee -a "$logPath"



# Rosetta runtime check
if [[ $(/usr/bin/uname -p) = 'arm' ]];
then
    echo "Log: $(date "+%F %T") Checking for Rosetta runtime" | tee -a "$logPath"
    if [[ ! -f /Library/Apple/usr/libexec/oah/libRosettaRuntime ]];
    then
        echo "Log: $(date "+%F %T") Rosetta runtime not present, installing Rosetta" | tee -a "$logPath"
        /usr/sbin/softwareupdate --install-rosetta --agree-to-license

        sleep 1

        echo "Log: $(date "+%F %T") Checking for other missing enrollment policies" | tee -a "$logPath"
        /usr/local/bin/jamf policy -event enrollmentComplete

        if [ ! -f /Library/Apple/usr/libexec/oah/libRosettaRuntime ];
        then
            echo "Log: $(date "+%F %T") Rosetta runtime still not present, trying install again" | tee -a "$logPath"
            /usr/sbin/softwareupdate --install-rosetta --agree-to-license
        fi
    else
        echo "Log: $(date "+%F %T") Rosetta runtime present" | tee -a "$logPath"
    fi
    echo "Log: $(date "+%F %T") Rosetta runtime check complete" | tee -a "$logPath"
fi



sleep 1



# Naming check
echo "Log: $(date "+%F %T") Checking for correct naming" | tee -a "$logPath"

if ! check_Name;
then
    echo "Log: $(date "+%F %T") Device name, $currentName, does not fit naming scheme" | tee -a "$logPath"
    /usr/local/bin/jamf policy -event rename
else
    echo "Log: $(date "+%F %T") Device name, $currentName, fits naming scheme" | tee -a "$logPath"
fi

echo "Log: $(date "+%F %T") Name check complete" | tee -a "$logPath"



sleep 1



# Jamf Connect check
echo "Log: $(date "+%F %T") Checking for Jamf Connect" | tee -a "$logPath"
if [[ ! -d "$jamf_connect_app" ]] || [[ ! -f "$jamf_connect_plist" ]];
then
    echo "Log: $(date "+%F %T") Missing Jamf Connect, installing" | tee -a "$logPath"
    /usr/local/bin/jamf policy -event MissingJamfConnect
else
    echo "Log: $(date "+%F %T") Jamf Connect already installed" | tee -a "$logPath"
fi



echo "Log: $(date "+%F %T") Exiting!" | tee -a "$logPath"
exit 0
