#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

check_already_running() {
    check_result="$1"
    event="$2"
    if [[ $check_result == *"already being run"* ]];
    then
    	echo "Log: Policy already being run, retrying in 60 seconds..."
        sleep 60
        check_result=$(/usr/local/bin/jamf policy -event $2)
        check_already_running "$check_result" "$event"
    fi
}

echo "Log: Checking for lingering enrollment policies..."
enrollment_check_result=$(/usr/local/bin/jamf policy -event enrollmentComplete)
check_already_running "$enrollment_check_result" "enrollmentComplete"
echo "Log: Enrollment policy check complete, continuing..."

sleep 1

echo "Log: Checking for remaining policies..."
policy_check_result=$(/usr/local/bin/jamf policy)
check_already_running "$policy_check_result" ""
echo "Log: Standard policy check complete, continuing..."

sleep 1

echo "Log: Updating inventory..."
inv_check_result=$(/usr/local/bin/jamf recon)
echo "Log: Inventory update complete, exiting..."

if [ ! $(/usr/bin/pgrep -q oahd) ] && [ $(/usr/bin/uname -p) = "arm" ];
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

exit 0
