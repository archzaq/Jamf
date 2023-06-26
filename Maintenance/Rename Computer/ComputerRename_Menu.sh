#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

# Information variables
currentName=$(hostname)
computerSerial=$(ioreg -l | grep IOPlatformSerialNumber | sed 's/"$//' | sed 's/.*"//')
serialShort=${computerSerial: -6}

# SLU standard naming scheme
standardName="SLU-$serialShort"

# Function to avoid repeating the scutil commands
function rename_Device() {
  /usr/sbin/scutil --set ComputerName $1
	/usr/sbin/scutil --set LocalHostName $1
	/usr/sbin/scutil --set HostName $1
	/usr/local/bin/jamf recon	
}

# Function to prompt user to choose device department prefix
function department_Prompt() {
	echo "Prompting user for department..."
	department=$(osascript <<YOO
		set dropdownResult to choose from list \
		{"1818", "AAS", "AAF", "ADM", "ANS", "AT", "BF", "BIO", "BIOC", "CADE",\
		"C4", "CFS", "CCO", "CHCE", "CHM", "CME", "COMPMED", "CSB", "CTO",\
		"DPS", "DRM", "DUR", "EAS", "EM", "ENG", "EU", "EVT", "FAC", "FCM",\
		"FHS", "GME", "GC", "HIS", "HER", "HR", "IPE", "IM", "IM-GI", "INTO",\
		"ITS", "LIB", "LAW", "MAR", "MED", "MED-ADM", "MM", "MMI", "MCL", "MCS",\
		"MOC", "NEU", "OB", "OPT", "ORT", "OTO", "PAR", "PAT", "PED", "PHARM",\
		"PHY", "POL", "PO", "PSY", "RAD", "REG", "RES", "SCJ", "SLUCOR", "SOE",\
		"SON", "SPH", "SPS", "SDEV", "SUR", "SW", "THE", "WMS"}\
		with title "SLU ITS: Device Rename" with prompt "Please choose your department:"
		return dropdownResult
YOO
)
	dept=$(echo "$department-")
	if [[ "$dept" == *"false"* ]];
	then
		echo "User canceled the operation."
		exit 0
	fi
	deptName="${dept}${serialShort}"
	echo "Current computer name is \"$currentName\"."
	echo "User chose the prefix \"$dept\"."
	echo "Renaming to \"$deptName\"."
    rename_Device "$deptName" # rename the device
	exit 0
}

# Function to ask the user if they want to rename the device
function rename_Ask() {
	renamePrompt=$(osascript <<OOP
	    set dialogResult to display dialog "This device name already contains a department prefix, would you like to choose a new one?\n\nCurrent Name: $currentName \n\nSelect \"Yes\" to continue, or \"Cancel\" to use the existing name." buttons {"Yes", "Cancel"} default button "Cancel" with title "SLU ITS: Device Rename" giving up after 300
	    if button returned of dialogResult is equal to "Yes" then
	        return "User selected: Yes"
	    else
	    	return "Dialog timed out"
	    end if
OOP
)
	echo "$renamePrompt"
}

# If the current device name contains "Mac",
# prompt the user to choose their department prefix.
if [[ $currentName == *"Mac"* ]];
then
	department_Prompt
# If the current device name already contains two hyphens,
# prompt the user if they want to choose a new prefix,
# if so, prompt the user to choose their department prefix.
elif [[ $currentName == *-*-* ]];
then
	longPrefix=$(echo "$currentName" | sed 's/\(.*-\).*$/\1/')
	newLongName="${longPrefix}${serialShort}"
	renameAnswer=$(rename_Ask) # GUI dialog for the user
	if [[ $renameAnswer == *"Yes"* ]];
	then
		department_Prompt
	else
		echo "Current computer name contains hyphens, \"$currentName\" with prefix \"$longPrefix\"."
		if [[ $currentName == $newLongName ]];
		then
			echo "Device already named correctly, \"$currentName\"."
			echo "Exiting..."
			exit 0
		else
			echo "Renaming to \"$newLongName\"."
			rename_Device "$newLongName"
			exit 0
		fi
	fi

# If the current device name already contains a hyphen,
# prompt the user if they want to choose a new prefix,
# if so, prompt the user to choose their department prefix.
elif [[ $currentName == *"-"* ]];
then
	prefix=$(echo "$currentName" | sed 's/\(.*-\).*/\1/')
	newName="${prefix}${serialShort}"
	renameAnswer=$(rename_Ask) # GUI dialog for the user
	if [[ $renameAnswer == *"Yes"* ]];
	then
		department_Prompt
	else
		echo "Current computer name contains a hyphen, \"$currentName\" with prefix \"$prefix\"."
		if [[ $currentName == $newName ]];
		then
			echo "Device already named correctly, \"$currentName\"."
			echo "Exiting..."
			exit 0
		else
			echo "Renaming to \"$newName\"."
			rename_Device "$newName"
			exit 0
		fi
	fi

# If the current device name fails to match any conditions,
# prompt the user to choose their department prefix.
else
	department_Prompt
fi
