#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 6-1-23    ###
### Updated: 6-21-24   ###
### Version: 1.1       ###
##########################

# Information variables
currentName=$(hostname)
computerSerial=$(ioreg -l | grep IOPlatformSerialNumber | sed 's/"$//' | sed 's/.*"//')
serialShort=${computerSerial: -6}

# SLU standard naming scheme
standardName="SLU-$serialShort"

# Contains scutil commands
function rename_Device() {
    /usr/sbin/scutil --set ComputerName $1
    /usr/sbin/scutil --set LocalHostName $1
    /usr/sbin/scutil --set HostName $1
    /usr/local/bin/jamf recon
}

# If the current device name contains "Mac",
# rename it using the SLU standard.
if [[ $currentName == *"Mac"* ]];
then
    echo "Current computer name contains 'Mac', \"$currentName\"."
    echo "Renaming to \"$standardName\"."
    rename_Device "$standardName"

# If the current device name already contains two hyphens,
# rename it using the pre-existing prefix and the final six characters of the serial number,
# exiting if the name is already correct.
elif [[ $currentName == *-*-* ]];
then
    longPrefix=$(echo "$currentName" | sed 's/\(.*-\).*$/\1/')
    newLongName="${longPrefix}${serialShort}"
    if [[ $currentName == $newLongName ]];
    then
        echo "Device already named correctly, \"$currentName\"."
        echo "Exiting..."
        exit 0
    fi
    echo "Current computer name contains hyphens, \"$currentName\" with prefix \"$longPrefix\"."
    echo "Renaming to \"$newLongName\"."
    rename_Device "$newLongName"

# If the current device name already contains a hyphen,
# rename it using the pre-existing prefix and the final six characters of the serial number,
# exiting if the name is already correct.
elif [[ $currentName == *"-"* ]];
then
    prefix=$(echo "$currentName" | sed 's/\(.*-\).*/\1/')
    newName="${prefix}${serialShort}"
    if [[ $currentName == $newName ]];
    then
        echo "Device already named correctly, \"$currentName\"."
        echo "Exiting..."
        exit 0
    fi
    echo "Current computer name contains a hyphen, \"$currentName\" with prefix \"$prefix\"."
    echo "Renaming to \"$newName\"."
    rename_Device "$newName"

# If the current device name fails to match any conditions,
# rename it using the SLU standard.
else
	echo "Current computer name matches no critera, \"$currentName\"."
	echo "Renaming to \"$standardName\"."
	rename_Device "$standardName"
fi

exit 0

