#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

# information variables
currentName=$(hostname)
computerSerial=$(ioreg -l | grep IOPlatformSerialNumber | sed 's/"$//' | sed 's/.*"//')
serialShort=${computerSerial: -6}

# SLU standard naming scheme
standardName="SLU-$serialShort"

# If the current device name contains "Mac",
# rename it using the SLU standard.
if [[ $currentName == *"Mac"* ]];
then
    /usr/sbin/scutil --set ComputerName $standardName
	/usr/sbin/scutil --set LocalHostName $standardName
	/usr/sbin/scutil --set HostName $standardName
	/usr/local/bin/jamf recon
	exit 0
# If the current device name already contains two hyphens,
# rename it using the pre-existing prefix and the final six characters of the serial number,
# exiting if the name is already correct.
elif [[ $currentName == *-*-* ]];
then
	longPrefix=$(echo "$currentName" | sed 's/\(.*-\).*$/\1/')
	newLongName="${longPrefix}${serialShort}"
	if [[ $currentName == $newLongName ]];
	then
		echo "Device already named correctly, exiting."
		exit 0
	fi
	echo "Computer name contains hyphens. $currentName with prefix $longPrefix"
	echo "Renaming to $newLongName"
	/usr/sbin/scutil --set ComputerName $newLongName
	/usr/sbin/scutil --set LocalHostName $newLongName
	/usr/sbin/scutil --set HostName $newLongName
	/usr/local/bin/jamf recon
    exit 0
# If the current device name already contains a hyphen,
# rename it using the pre-existing prefix and the final six characters of the serial number,
# exiting if the name is already correct.
elif [[ $currentName == *"-"* ]];
then
	prefix=$(echo "$currentName" | sed 's/\(.*-\).*/\1/')
	newName="${prefix}${serialShort}"
	if [[ $currentName == $newName ]];
	then
		echo "Device already named correctly, exiting."
		exit 0
	fi
	echo "Computer name contains hyphen. $currentName with prefix $prefix"
	echo "Renaming to $newName"
	/usr/sbin/scutil --set ComputerName $newName
	/usr/sbin/scutil --set LocalHostName $newName
	/usr/sbin/scutil --set HostName $newName
	/usr/local/bin/jamf recon
    exit 0
# If the current device name fails to match any conditions,
# rename it using the SLU standard.
else
	/usr/sbin/scutil --set ComputerName $standardName
	/usr/sbin/scutil --set LocalHostName $standardName
	/usr/sbin/scutil --set HostName $standardName
	/usr/local/bin/jamf recon
	exit 0
fi

