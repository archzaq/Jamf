#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 7-12-23   ###
### Updated: 6-20-24   ###
### Version: 1.0       ###
##########################

readonly jamf_connect_plist="/Library/Managed Preferences/com.jamf.connect.plist"
readonly jamf_connect_app="/Applications/Jamf Connect.app"

# Often there is a jamf action already running in the background after enrollment.
# This is an attempt at handling that
check_already_running() {
    check_result="$1"
    event="$2"
    if [[ $check_result == *"already being run"* ]];
    then
    	echo "Log: Policy already being run, retrying in 60 seconds..."
        sleep 60
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

echo "Log: Checking for lingering enrollment policies..."
enrollment_check_result=$(/usr/local/bin/jamf policy -event enrollmentComplete)
check_already_running "$enrollment_check_result" "enrollmentComplete"
echo "Log: Enrollment policy check complete, continuing..."

sleep 1

echo "Log: Checking for remaining policies..."
policy_check_result=$(/usr/local/bin/jamf policy)
check_already_running "$policy_check_result"
echo "Log: Standard policy check complete, continuing..."

sleep 1

echo "Log: Updating inventory..."
/usr/local/bin/jamf recon
echo "Log: Inventory update complete, exiting..."

if [[ $(/usr/bin/uname -p) = "arm" ]] && [[ ! $(/usr/bin/pgrep -q oahd) ]];
then
    echo "Log: Rosetta not running, installing Rosetta"
    /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    sleep 1
    /usr/local/bin/jamf policy -event enrollmentComplete
    if [ ! $(/usr/bin/pgrep -q oahd) ];
    then
        echo "Log: Rosetta still not running, trying again"
    	/usr/sbin/softwareupdate --install-rosetta --agree-to-license
    fi
    if $(/usr/bin/pgrep -q oahd);
    then
        echo "Log: Rosetta installed"
    else
        echo "Log: Rosetta not installed"
    fi
fi

if [[ ! -d "$jamf_connect_app" ]] || [[ ! -f "$jamf_connect_plist" ]];
then
    echo "Log: Missing Jamf Connect, installing"
    /usr/local/bin/jamf policy -event MissingJamfConnect
fi

exit 0
