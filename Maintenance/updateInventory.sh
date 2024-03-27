#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

check_already_running() {
    local check_result="$1"
    local event="$2"
    local retry_count=0
    if [[ $check_result == *"already being run"* ]];
    then
        while [[ $check_result == *"already being run"* ]];
		do
            ((retry_count++))
			if [ "$retry_count" -ge 11 ];
			then
				echo "Log: Retry limit reached. Exiting function"
				return
            fi
            echo "Log: Policy already being run, retrying in 60 seconds... (Retry $retry_count)"
            sleep 60
            if [ -z "$event" ];
			then
                check_result=$(/usr/local/bin/jamf policy)
            else
                check_result=$(/usr/local/bin/jamf policy -event "$event")
            fi
        done
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

    if [ $(/usr/bin/pgrep -q oahd) ];
    then
        echo "Log: Rosetta installed"
    else
        echo "Log: Rosetta not installed"
    fi
fi


# If the current name contains Mac or SLU, run rename
currentName=$(hostname)
if [[ $currentName == *"Mac"* ]];
then
    /usr/local/bin/jamf policy -event rename
elif [[ $currentName == "SLU-"* ]];
then
    /usr/local/bin/jamf policy -event rename
fi

exit 0
