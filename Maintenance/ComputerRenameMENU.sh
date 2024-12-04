#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 6-28-23   ###
### Updated: 12-4-24   ###
### Version: 2.1       ###
##########################

readonly currentName=$(/usr/sbin/scutil --get LocalHostName)
readonly computerSerial=$(ioreg -l | grep IOPlatformSerialNumber | sed 's/"$//' | sed 's/.*"//')
readonly serialShort=${computerSerial: -6}
readonly logPath='/var/log/computerRenameMenu.log'
readonly iconPath='/usr/local/jamfconnect/SLU.icns'
readonly dialogTitle='SLU ITS: Computer Rename'

# Check for SLU icon file, applescript dialog boxes will error without it
function icon_Check() {
    if [[ ! -f "$iconPath" ]];
    then
        echo "Log: $(date "+%F %T") No SLU icon found, attempting install." | tee -a "$logPath"
        /usr/local/bin/jamf policy -event SLUFonts
        if [[ ! -f "$iconPath" ]];
        then
            echo "Log: $(date "+%F %T") Unable to locate SLU icon found." | tee -a "$logPath"
            return 1
        fi
    fi
    echo "Log: $(date "+%F %T") SLU icon found." | tee -a "$logPath"
    return 0
}

# Check if someone is logged into the device
function login_Check() {
    local account="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
    if [[ "$account" == 'root' ]] || [[ "$account" == '_mbsetupuser' ]];
    then
        echo "Log: $(date "+%F %T") \"$account\" currently logged in." | tee -a "$logPath"
        return 1
    elif [[ "$account" == 'loginwindow' ]] || [[ -z "$account" ]];
    then
        echo "Log: $(date "+%F %T") No one logged in." | tee -a "$logPath"
        return 1
    else
        echo "Log: $(date "+%F %T") \"$account\" currently logged in." | tee -a "$logPath"
        return 0
    fi
}

# Ask the user if they want to rename the device
function rename_Ask() {
    renamePrompt=$(osascript <<OOP
        set dialogResult to display dialog "This device name already contains a department prefix, would you like to choose a new one?\n\nCurrent Name: $currentName" buttons {"Keep", "Change"} default button "Keep" with icon POSIX file "$iconPath" with title "$dialogTitle" giving up after 900
        if button returned of dialogResult is equal to "Change" then
            return "User selected: Change"
        else
            return "Dialog timed out"
        end if
OOP
	)
	echo "$renamePrompt"
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
    echo "Log: $(date "+%F %T") Prompting user for department." | tee -a "$logPath"
    department=$(osascript <<YOO
        set dropdownResult to choose from list \
        {"1818 - 1818 Program", "AAS - African-American Studies", "AAF - Academic Affairs",\
        "ADM - Administration Arts and Sciences", "AHP - Allied Health Professions", "AMS - American Studies", "AT - Athletics", "Academic Tech Commons", "BF - Business & Finance",\
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
        "PHYS - Physics", "POL - Political Science", "PO - President's Office", "PP - Prison Program", "PVST - Provost", "PSY - Psychology",\
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
        echo "Log: $(date "+%F %T") User canceled the operation." | tee -a "$logPath"
        exit 0
    # Run the lab_Prompt function for lab devices
    elif [[ "echo $department" == *"Lab Device"* ]];
    then
        lab_Prompt # lab prompt function
    # Run the atc_Prompt function for atc devices
    elif [[ "echo $department" == *"Academic Tech Commons"* ]];
    then
        atc_Prompt # atc prompt function
    # Anyone that didnt select cancel, lab, or atc, rename using chosen option
    else
        deptName="${dept}-${serialShort}"
        echo "Log: $(date "+%F %T") User chose the prefix \"$dept\"." | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Current computer name is \"$currentName\"." | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Renaming to \"$deptName\"." | tee -a "$logPath"
        rename_Device "$deptName" # rename device function
    fi
}

# Seperate dialog list for lab devices
function lab_Prompt(){
    echo "Log: $(date "+%F %T") User chose \"Lab Device\"." | tee -a "$logPath"
    labList=$(osascript <<YOO
        set dropdownResult to choose from list \
        {"216 - Des Peres", "103 - Macelwane", "2104 - Morrissey", "202 - Xavier", "207 - Xavier", "220 - Xavier", "236 - Xavier"}\
        with title "$dialogTitle" with prompt "Please choose the Lab in which this device will be located:"
        return dropdownResult
YOO
	)
    lab=$(echo "$labList")
    labPrefix=$(echo "$lab" | sed 's/\(.*\) - .*/\1/' | sed 's/[[:space:]]*$//')
    # Cancels the operation if the user selects Cancel from the osascript prompt
    if [[ "$lab" == *"false"* ]];
    then
        echo "Log: $(date "+%F %T") User canceled the operation." | tee -a "$logPath"
        department_Prompt
    # Name appropriately for Des Peres
    elif [[ "$lab" == *"Des Peres"* ]];
    then
        labName="DP-${labPrefix}-$serialShort"
        echo "Log: $(date "+%F %T") User chose \"Des Peres lab $labPrefix\"." | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Renaming device to \"$labName\"." | tee -a "$logPath"
        rename_Device "$labName"
        exit 0
   # Name appropriately for Macelwane
    elif [[ "$lab" == *"Macelwane"* ]];
    then
        labName="MWH-${labPrefix}-$serialShort"
        echo "Log: $(date "+%F %T") User chose \"Macelwane lab $labPrefix\"." | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Renaming device to \"$labName\"." | tee -a "$logPath"
        rename_Device "$labName"
        exit 0
    # Name appropriately for Xavier
    elif [[ "$lab" == *"Xavier"* ]];
    then
        labName="XVH-${labPrefix}-$serialShort"
        echo "Log: $(date "+%F %T") User chose \"Xavier lab $labPrefix\"." | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Renaming device to \"$labName\"." | tee -a "$logPath"
        rename_Device "$labName"
        exit 0
    # Name appropriately for Morrissey
    elif [[ "$lab" == *"Morrissey"* ]];
    then
        labName="MOR-${labPrefix}-$serialShort"
        echo "Log: $(date "+%F %T") User chose \"Morrissey lab $labPrefix\"." | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Renaming device to \"$labName\"." | tee -a "$logPath"
        rename_Device "$labName"
        exit 0
    # Just in case
    else
        echo "Log: $(date "+%F %T") Error'd out." | tee -a "$logPath"
        exit 1
    fi
}

# Seperate dialog list for atc devices
function atc_Prompt() {
    echo "Log: $(date "+%F %T") User chose \"ATC Device\"." | tee -a "$logPath"
    atcList=$(osascript <<YOO
        set dropdownResult to choose from list \
        {"ATC - General", "LNR - Loaner"}\
        with title "$dialogTitle" with prompt "Please choose the ATC area in which this device will be located:"
        return dropdownResult
YOO
	)
    atcArea=$(echo "$atcList")
    atcPrefix=$(echo "$atcArea" | sed 's/\(.*\) - .*/\1/' | sed 's/[[:space:]]*$//')
    # Cancels the operation if the user selects Cancel from the osascript prompt
    if [[ "$atcArea" == *"false"* ]];
    then
        echo "Log: $(date "+%F %T") User canceled the operation." | tee -a "$logPath"
        department_Prompt
    # Name appropriately for general ATC
    elif [[ "$atcArea" == *"General"* ]];
    then
        atcName="${atcPrefix}-$serialShort"
        echo "Log: $(date "+%F %T") User chose \"General $atcPrefix\"." | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Renaming device to \"$atcName\"." | tee -a "$logPath"
        rename_Device "$atcName"
        exit 0
    elif [[ "$atcArea" == *"Loaner"* ]];
    then
        atcName="ATC-${atcPrefix}-$serialShort"
        echo "Log: $(date "+%F %T") User chose \"Loaner $atcPrefix\"." | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Renaming device to \"$atcName\"." | tee -a "$logPath"
        rename_Device "$atcName"
        exit 0
    else
        echo "Log: $(date "+%F %T") Error'd out." | tee -a "$logPath"
        exit 1
    fi
}

function main() {
    echo "Log: $(date "+%F %T") Beginning computer rename script." | tee "$logPath"

    # Check for SLU icon file
    echo "Log: $(date "+%F %T") Checking for SLU icon." | tee -a "$logPath"
    if ! icon_Check;
    then
        echo "Log: $(date "+%F %T") Exiting for no SLU icon." | tee -a "$logPath"
        exit 1
    fi



    # Check for valid user being logged in
    echo "Log: $(date "+%F %T") Checking for currently logged in user." | tee -a "$logPath"
    if ! login_Check;
    then
        echo "Log: $(date "+%F %T")Exiting for invalid user logged in." | tee -a "$logPath"
        exit 1
    fi



    # If the current device name contains "Mac",
    # prompt the user to choose their department prefix.
    if [[ $currentName == *"Mac"* ]];
    then
        echo "Log: $(date "+%F %T") Device name contains \"Mac\"." | tee -a "$logPath"
        department_Prompt # department prompt function
        
    # If the current device name already contains two hyphens, prompt the user to select a new prefix, if they want.
    # If so, prompt the user to choose their department prefix.
    elif [[ $currentName == *-*-* ]];
    then
        echo "Log: $(date "+%F %T") Device name contains a double prefix." | tee -a "$logPath"
        longPrefix=$(echo "$currentName" | sed 's/\(.*-\).*$/\1/')
        newLongName="${longPrefix}${serialShort}"
        renameAnswer=$(rename_Ask) # rename prompt function
        if [[ $renameAnswer == *"Change"* ]];
        then
            department_Prompt # department prompt function
        else
            echo "Log: $(date "+%F %T") Current computer name contains hyphens, \"$currentName\" with prefix \"$longPrefix\"." | tee -a "$logPath"
            if [[ $currentName == $newLongName ]];
            then
                echo "Log: $(date "+%F %T") Device already named correctly, \"$currentName\"." | tee -a "$logPath"
                echo "Log: $(date "+%F %T") Exiting." | tee -a "$logPath"
            else
                echo "Log: $(date "+%F %T") Renaming to \"$newLongName\"." | tee -a "$logPath"
                rename_Device "$newLongName" # rename device function
            fi
        fi

    # If the current device name already contains a hyphen, prompt the user if they want to choose a new prefix.
    # If so, prompt the user to choose their department prefix.
    elif [[ $currentName == *"-"* ]];
    then
        echo "Log: $(date "+%F %T") Device name contains a prefix." | tee -a "$logPath"
        prefix=$(echo "$currentName" | sed 's/\(.*-\).*/\1/')
        newName="${prefix}${serialShort}"
        if [[ ! "$prefix" == 'SLU-' ]];
        then
            renameAnswer=$(rename_Ask) # rename prompt function
            if [[ $renameAnswer == *"Change"* ]];
            then
                department_Prompt # department prompt function
            else
                echo "Log: $(date "+%F %T") Current computer name contains a hyphen, \"$currentName\" with prefix \"$prefix\"." | tee -a "$logPath"
                if [[ $currentName == $newName ]];
                then
                    echo "Log: $(date "+%F %T") Device already named correctly, \"$currentName\"." | tee -a "$logPath"
                    echo "Log: $(date "+%F %T") Exiting." | tee -a "$logPath"
                else
                    echo "Log: $(date "+%F %T") Renaming to \"$newName\"." | tee -a "$logPath"
                    rename_Device "$newName" # rename device function
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

