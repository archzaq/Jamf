#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

# Information variables
currentName=$(hostname)
computerSerial=$(ioreg -l | grep IOPlatformSerialNumber | sed 's/"$//' | sed 's/.*"//')
serialShort=${computerSerial: -6}

# Contains scutil commands
function rename_Device() {
    /usr/sbin/scutil --set ComputerName $1
	/usr/sbin/scutil --set LocalHostName $1
	/usr/sbin/scutil --set HostName $1
	/usr/local/bin/jamf recon	
}

# Prompts user to choose device department prefix
function department_Prompt() {
	echo "Prompting user for department..."
	department=$(osascript <<YOO
		set dropdownResult to choose from list \
		{"1818 - 1818 Program", "AAS - African-American Studies", "AAF - Academic Affairs",\
		"ADM - Administration Arts and Sciences", "AMS - American Studies", "AT - Athletics", "ATC - Academic Tech Commons", "BF - Business & Finance",\
		"BIO - Biology", "BIOC - Biochemistry", "CADE - Center for Advanced Dental Education",\
		"CFS - Center for Sustainability", "CHCE - Center for HealthCare Ethics", "CHM - Chemistry",\
		"CME - Continuing Medical Education(PAWS)", "CMM - Communications", "COMPMED - Comparative Medicine ",\
		"CSB - Cook School of Business","CSD - Speech, Language, and Hearing Sciences", "CTO - Clinical Trial Office",\
		"DPS - Department of Public Safety", "DUR - University Development","FPA - Fine & Performing Arts",\
		"EAS - Earth and Atmospheric Science", "EM - Enrollment Management", "ENG - English",\
		"EU - Clinical Skill", "EVT - Event Services", "FAC - Facilities",\
		"GC - Office of General Counsel", "HIS - History", "HR - Human Resources",\
		"IPE - Interprofessional Education Program", "IM-GI - GI-Research", "INTO - INTO_SLU",\
		"ITS - Information Technology Services", "Lab Device", "LIB - Libraries", "LAW - School of Law",\
		"MAR - Marketing & Communications", "MED - Medical School", "MM - Mission & Ministry",\
		"MMI - Molecular Microbiology and Immunology", "MCL - Language Literature and Cultures",\
		"MCS - Math and Mathematical Computer Science", "MOC - Museum of Contemporary Religious Art",\
		"PAR - Parks College", "PHARM - Pharmacology and Physiology","PHY - Philosophy",\
		"PHYS - Physics", "POL - Political Science", "PO - President's Office", "PVST - Provost", "PSY - Psychology",\
		"REG - Office of the Registrar", "RES - Research Admin", "SCJ - Sociology and Anthropology",\
		"SLUCOR - SLU Center of Outcomes Research", "SOE - School of Education",\
		"SON - School of Nursing", "SPH - School of Public Health",\
		"SPS - School of Professional Studies", "SDEV - Student Development", "SW - Social Work",\
		"THE - Theological Studies", "WMS - Women’s Studies Program"}\
		with title "SLU ITS: Device Rename" with prompt "Please choose your department:"
		return dropdownResult
YOO
	)
	# sed command to only grab the text before the ' - ' in the list options
	dept=$(echo "$department" | sed 's/\(.*\) - .*/\1/' | sed 's/[[:space:]]*$//')
	# Cancels the operation if the user selects Cancel from the osascript prompt
	if [[ "$dept" == *"false"* ]];
	then
		echo "User canceled the operation."
		exit 0
	# Run the lab_Prompt function for lab devices
	elif [[ "echo $department" == *"Lab Device"* ]];
	then
		lab_Prompt # lab prompt function
	# Anyone that didnt cancel or select lab device, rename using chosen option
	else
		deptName="${dept}-${serialShort}"
		echo "User chose the prefix \"$dept\"."
		echo "Current computer name is \"$currentName\"."
		echo "Renaming to \"$deptName\"."
	    rename_Device "$deptName" # rename device function
	    exit 0
	fi
}

# Seperate dialog list for lab devices
function lab_Prompt(){
	echo "User chose \"Lab Device\""
	labList=$(osascript <<YOO
		set dropdownResult to choose from list \
		{"103 - Macelwane", "202 - Xavier", "207 - Xavier", "220 - Xavier", "236 - Xavier"}\
		with title "SLU ITS: Device Rename" with prompt "Please choose the Lab in which this device will be located:"
		return dropdownResult
YOO
	)
	lab=$(echo "$labList")
	labPrefix=$(echo "$lab" | sed 's/\(.*\) - .*/\1/' | sed 's/[[:space:]]*$//')
	# Cancels the operation if the user selects Cancel from the osascript prompt
	if [[ "$lab" == *"false"* ]];
	then
		echo "User canceled the operation."
		exit 1
	# Name appropriately for Macelwane
	elif [[ "$lab" == *"Macelwane"* ]];
	then
		labName="MWH-${labPrefix}-$serialShort"
		echo "User chose \"Macelwane lab $labPrefix\""
		echo "Renaming device to \"$labName\""
		rename_Device "$labName"
		exit 0
	# Name appropriately for Xavier
	elif [[ "$lab" == *"Xavier"* ]];
	then
		labName="XVH-${labPrefix}-$serialShort"
		echo "User chose \"Xavier lab $labPrefix\""
		echo "Renaming device to \"$labName\""
		rename_Device "$labName"
		exit 0
	# Just in case
	else
		echo "Error'd out"
		exit 1
	fi
}

# Ask the user if they want to rename the device
function rename_Ask() {
	renamePrompt=$(osascript <<OOP
	    set dialogResult to display dialog "This device name already contains a department prefix, would you like to choose a new one?\n\nCurrent Name: $currentName \n\nSelect \"Yes\" to continue, or \"Cancel\" to use the existing prefix." buttons {"Yes", "Cancel"} default button "Cancel" with title "SLU ITS: Device Rename" giving up after 300
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
	department_Prompt # department prompt function
	
# If the current device name already contains two hyphens,
# prompt the user to select a new prefix,
# if so, prompt the user to choose their department prefix.
elif [[ $currentName == *-*-* ]];
then
	longPrefix=$(echo "$currentName" | sed 's/\(.*-\).*$/\1/')
	newLongName="${longPrefix}${serialShort}"
	renameAnswer=$(rename_Ask) # rename prompt function
	if [[ $renameAnswer == *"Yes"* ]];
	then
		department_Prompt # department prompt function
	else
		echo "Current computer name contains hyphens, \"$currentName\" with prefix \"$longPrefix\"."
		if [[ $currentName == $newLongName ]];
		then
			echo "Device already named correctly, \"$currentName\"."
			echo "Exiting..."
			exit 0
		else
			echo "Renaming to \"$newLongName\"."
			rename_Device "$newLongName" # rename device function
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
	renameAnswer=$(rename_Ask) # rename prompt function
	if [[ $renameAnswer == *"Yes"* ]];
	then
		department_Prompt # department prompt function
	else
		echo "Current computer name contains a hyphen, \"$currentName\" with prefix \"$prefix\"."
		if [[ $currentName == $newName ]];
		then
			echo "Device already named correctly, \"$currentName\"."
			echo "Exiting..."
			exit 0
		else
			echo "Renaming to \"$newName\"."
			rename_Device "$newName" # rename device function
			exit 0
		fi
	fi

# If the current device name fails to match any conditions,
# prompt the user to choose their department prefix.
else
	department_Prompt # department prompt function
fi
