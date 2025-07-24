#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 06-28-23  ###
### Updated: 07-24-25  ###
### Version: 2.8       ###
##########################

readonly currentName=$(/usr/sbin/scutil --get LocalHostName)
readonly computerSerial=$(ioreg -l | grep IOPlatformSerialNumber | sed 's/"$//' | sed 's/.*"//')
readonly serialShort=${computerSerial: -6}
readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly defaultIconPath='/usr/local/jamfconnect/SLU.icns'
readonly genericIconPath='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
readonly logPath='/var/log/computerRenameMenu.log'
readonly dialogTitle='SLU ITS: Computer Rename'

# Append current status to log file
function log_Message() {
    local timestamp="$(date "+%F %T")"
    printf "Log: %s %s\n" "$timestamp" "$1" | tee -a "$logPath"
}

# Check for valid icon file, AppleScript dialog boxes will error without it
function icon_Check() {
    effectiveIconPath="$defaultIconPath"
    if [[ ! -f "$effectiveIconPath" ]];
    then
        log_Message "No SLU icon found"
        if [[ -f '/usr/local/bin/jamf' ]];
        then
            log_Message "Attempting icon install via Jamf"
            /usr/local/bin/jamf policy -event SLUFonts
        else
            log_Message "No Jamf binary found"
        fi
        if [[ ! -f "$effectiveIconPath" ]];
        then
            if [[ -f "$genericIconPath" ]];
            then
                log_Message "Generic icon found"
                effectiveIconPath="$genericIconPath"
            else
                log_Message "Generic icon not found"
                return 1
            fi
        fi
    else
        log_Message "SLU icon found"
    fi
    return 0
}

# Check if someone is logged into the device
function login_Check() {
    if [[ "$currentUser" == 'root' ]] || [[ "$currentUser" == 'loginwindow' ]] || [[ -z "$currentUser" ]] || [[ "$currentUser" == '_mbsetupuser' ]];
    then
        log_Message "Invalid user logged in: $currentUser"
        return 1
    else
        log_Message "Valid user logged in: $currentUser"
        return 0
    fi
}

# Ask the user if they want to rename the device
function rename_Prompt() {
    renameResult=$(osascript <<OOP
        set dialogResult to display dialog "This device name already contains a department prefix, would you like to choose a new one?\n\nCurrent Name: $currentName" buttons {"Keep", "Change"} default button "Keep" with icon POSIX file "$effectiveIconPath" with title "$dialogTitle" giving up after 900
        if button returned of dialogResult is equal to "Change" then
            return "User selected: Change"
        else
            return "Dialog timed out"
        end if
OOP
	)
}

# Contains scutil commands to change device name
function rename_Device() {
    local name="$1"
    /usr/sbin/scutil --set ComputerName $name
    /usr/sbin/scutil --set LocalHostName $name
    /usr/sbin/scutil --set HostName $name
    /usr/local/bin/jamf recon	
}

# Prompts user to choose device department prefix
function department_Prompt() {
    log_Message "Prompting user for department"
    department=$(osascript <<OOP
    set dropdownResult to choose from list \
    {"1818 - 1818 Program", "AAS - African-American Studies", "AAF - Academic Affairs", "ADM - Administration Arts and Sciences",\
    "AHP - Allied Health Professions", "AMS - American Studies", "AT - Athletics", "Academic Tech Commons", "BF - Business & Finance",\
    "BIO - Biology", "BIOC - Biochemistry", "CADE - Center for Advanced Dental Education", "CASE - Ctr for Anatomical Science & Ed-Administration",\
    "CFS - Center for Sustainability", "CHCE - Center for HealthCare Ethics", "CHM - Chemistry",\
    "CME - Continuing Medical Education(PAWS)", "CMM - Communications", "COMPMED - Comparative Medicine ", "CSB - Cook School of Business",\
    "CSD - Speech, Language, and Hearing Sciences", "CTO - Clinical Trial Office", "CWOD - Ctr for Workforce & Org Development",\
    "DPS - Department of Public Safety", "DUR - University Development","FPA - Fine & Performing Arts",\
    "EAS - Earth and Atmospheric Science", "EM - Enrollment Management", "ENG - English",\
    "EU - Clinical Skill", "EVT - Event Services", "FAC - Facilities",\
    "GC - Office of General Counsel", "HIS - History", "HR - Human Resources",\
    "IPE - Interprofessional Education Program", "IM - Internal Medicine", "IM-GI - GI-Research", "INTO - INTO_SLU",\
    "ITS - Information Technology Services", "Lab Device", "LIB - Libraries", "LAW - School of Law",\
    "MAR - Marketing & Communications", "MED - Medical School", "MM - Mission & Ministry",\
    "MMI - Molecular Microbiology and Immunology", "MCL - Language Literature and Cultures",\
    "MCS - Math and Mathematical Computer Science", "MOC - Museum of Contemporary Religious Art", "NEU - Neurology",\
    "PATH - Pathology", "PAR - Parks College", "PEDS - Pediatrics", "PHARM - Pharmacology and Physiology","PHY - Philosophy",\
    "PHYS - Physics", "POL - Political Science", "PO - President's Office", "PP - Prison Program", "PVST - Provost", "PSY - Psychology",\
    "REG - Office of the Registrar", "RES - Research Admin", "SCJ - Sociology and Anthropology",\
    "SLUCOR - SLU Center of Outcomes Research", "SOE - School of Education", "SON - School of Nursing", "SPH - School of Public Health",\
    "SPS - School of Professional Studies", "SDEV - Student Development", "SW - Social Work",\
    "THE - Theological Studies", "WMS - Women’s Studies Program"} \
    with title "$dialogTitle" with prompt "Please choose your department:"
    return dropdownResult
OOP
	)
    dept=$(echo "$department" | sed 's/\(.*\) - .*/\1/' | sed 's/[[:space:]]*$//')
    if [[ "$dept" == *"false"* ]];
    then
        log_Message "User canceled the operation"
        exit 0
    elif [[ "$department" == *"Lab Device"* ]];
    then
        lab_Prompt
    elif [[ "$department" == *"Academic Tech Commons"* ]];
    then
        atc_Prompt
    else
        deptName="${dept}-${serialShort}"
        log_Message "User chose: \"$dept\""
        log_Message "Current computer name: \"$currentName\""
        log_Message "Renaming device to \"$deptName\""
        rename_Device "$deptName"
    fi
}

# Seperate dialog list for lab devices
function lab_Prompt(){
    log_Message "User chose: \"Lab Device\""
    chosenLab=$(osascript <<YOO
    set dropdownResult to choose from list \
    {"216 - Des Peres", "2104 - Morrissey", "202 - Xavier", "207 - Xavier", "220 - Xavier", "236 - Xavier"}\
    with title "$dialogTitle" with prompt "Please choose the Lab in which this device will be located:"
    return dropdownResult
YOO
	)
    labPrefix=$(echo "$chosenLab" | sed 's/\(.*\) - .*/\1/' | sed 's/[[:space:]]*$//')
    # Cancels the operation if the user selects Cancel from the osascript prompt
    if [[ "$chosenLab" == *"false"* ]];
    then
        log_Message "User canceled the operation"
        department_Prompt
    # Name appropriately for Des Peres
    elif [[ "$chosenLab" == *"Des Peres"* ]];
    then
        labName="DP-${labPrefix}-$serialShort"
        log_Message "User chose: \"Des Peres lab $labPrefix\""
        log_Message "Renaming device to \"$labName\""
        rename_Device "$labName"
    # Name appropriately for Xavier
    elif [[ "$chosenLab" == *"Xavier"* ]];
    then
        labName="XVH-${labPrefix}-$serialShort"
        log_Message "User chose: \"Xavier lab $labPrefix\""
        log_Message "Renaming device to \"$labName\""
        rename_Device "$labName"
    # Name appropriately for Morrissey
    elif [[ "$chosenLab" == *"Morrissey"* ]];
    then
        labName="MOR-${labPrefix}-$serialShort"
        log_Message "User chose: \"Morrissey lab $labPrefix\""
        log_Message "Renaming device to \"$labName\""
        rename_Device "$labName"
    # Just in case
    else
        log_Message "Error'd out"
        exit 1
    fi
}

# Seperate dialog list for atc devices
function atc_Prompt() {
    log_Message "User chose: \"ATC Device\""
    chosenATC=$(osascript <<YOO
    set dropdownResult to choose from list {"ATC - General", "LNR - Loaner"}\
    with title "$dialogTitle" with prompt "Please choose the ATC area in which this device will be located:"
    return dropdownResult
YOO
	)
    atcPrefix=$(echo "$chosenATC" | sed 's/\(.*\) - .*/\1/' | sed 's/[[:space:]]*$//')
    if [[ "$chosenATC" == *"false"* ]];
    then
        log_Message "User canceled the operation."
        department_Prompt
    elif [[ "$chosenATC" == *"General"* ]];
    then
        atcName="${atcPrefix}-$serialShort"
        log_Message "User chose: \"General $atcPrefix\""
        log_Message "Renaming device to \"$atcName\""
        rename_Device "$atcName"
    elif [[ "$chosenATC" == *"Loaner"* ]];
    then
        atcName="ATC-${atcPrefix}-$serialShort"
        log_Message "User chose: \"Loaner $atcPrefix\""
        log_Message "Renaming device to \"$atcName\""
        rename_Device "$atcName"
    else
        log_Message "Error'd out"
        exit 1
    fi
}

function main() {
    printf "Log: $(date "+%F %T") Beginning Computer Rename Menu script\n" | tee "$logPath"

    # Check for SLU icon file
    log_Message "Checking for SLU icon"
    if ! icon_Check;
    then
        log_Message "Exiting for no valid icon file"
        exit 1
    fi

    # Check for valid user being logged in
    log_Message "Checking for currently logged in user"
    if ! login_Check;
    then
        log_Message "Exiting for invalid user logged in"
        exit 1
    fi

    # If the current device name contains "Mac",
    # prompt the user to choose their department prefix.
    if [[ $currentName == *"Mac"* ]];
    then
        log_Message "Device name contains \"Mac\""
        department_Prompt
        
    # If the current device name already contains two hyphens, prompt the user to select a new prefix, if they want.
    # If so, prompt the user to choose their department prefix.
    elif [[ $currentName == *-*-* ]];
    then
        log_Message "Device name contains a double prefix"
        longPrefix=$(echo "$currentName" | sed 's/\(.*-\).*$/\1/')
        newLongName="${longPrefix}${serialShort}"
        rename_Prompt
        if [[ $renameResult == *"Change"* ]];
        then
            department_Prompt
        else
            log_Message "Current computer name contains hyphens, \"$currentName\" with prefix \"$longPrefix\""
            if [[ $currentName == $newLongName ]];
            then
                log_Message "Device already named correctly: \"$currentName\""
            else
                log_Message "Renaming device to \"$newLongName\""
                rename_Device "$newLongName"
            fi
        fi

    # If the current device name already contains a hyphen, prompt the user if they want to choose a new prefix.
    # If so, prompt the user to choose their department prefix.
    elif [[ $currentName == *"-"* ]];
    then
        log_Message "Device name contains a prefix"
        prefix=$(echo "$currentName" | sed 's/\(.*-\).*/\1/')
        newName="${prefix}${serialShort}"
        if [[ ! "$prefix" == 'SLU-' ]];
        then
            rename_Prompt
            if [[ $renameResult == *"Change"* ]];
            then
                department_Prompt
            else
                log_Message "Current computer name contains a hyphen, \"$currentName\" with prefix \"$prefix\""
                if [[ $currentName == $newName ]];
                then
                    log_Message "Device already named correctly: \"$currentName\""
                else
                    log_Message "Renaming device to \"$newName\""
                    rename_Device "$newName"
                fi
            fi
        else
            department_Prompt
        fi

    # If the current device name fails to match any conditions,
    # prompt the user to choose their department prefix.
    else
        department_Prompt # department prompt function
    fi

    exit 0
}

main

