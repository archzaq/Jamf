#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 6-1-23    ###
### Updated: 10-4-24   ###
### Version: 2.0       ###
##########################

readonly currentName=$(/usr/sbin/scutil --get LocalHostName)
readonly computerSerial=$(ioreg -l | grep IOPlatformSerialNumber | sed 's/"$//' | sed 's/.*"//')
readonly serialShort=${computerSerial: -6}
readonly logPath='/var/log/computerRename_Background.log'
standardName="SLU-$serialShort"

# Contains scutil commands to change device name
function rename_Device() {
    local name="$1"
    /usr/sbin/scutil --set ComputerName $name
    /usr/sbin/scutil --set LocalHostName $name
    /usr/sbin/scutil --set HostName $name
    /usr/local/bin/jamf recon	

    echo "Log: $(date "+%F %T") Device renamed." | tee -a "$logPath"
}

echo "Log: $(date "+%F %T") Beginning computer rename script." | tee "$logPath"

# If the current device name contains "Mac",
# rename it using the SLU standard.
if [[ $currentName == *"Mac"* ]];
then
    echo "Log: $(date "+%F %T") Device name contains \"Mac\"." | tee -a "$logPath"
    echo "Log: $(date "+%F %T") Renaming to \"$standardName\"." | tee -a "$logPath"
    rename_Device "$standardName"

# If the current device name already contains two hyphens,
# rename it using the pre-existing prefix and the final six characters of the serial number,
# exiting if the name is already correct.
elif [[ $currentName == *-*-* ]];
then
    echo "Log: $(date "+%F %T") Device name contains a double prefix." | tee -a "$logPath"
    longPrefix=$(echo "$currentName" | sed 's/\(.*-\).*$/\1/')
    newLongName="${longPrefix}${serialShort}"
    if [[ $currentName == $newLongName ]];
    then
        echo "Log: $(date "+%F %T") Device already named correctly, \"$currentName\"." | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Exiting." | tee -a "$logPath"
    else
        echo "Log: $(date "+%F %T") Current computer name contains hyphens, \"$currentName\" with prefix \"$longPrefix\"." | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Renaming to \"$newLongName\"." | tee -a "$logPath"
        rename_Device "$newLongName"
    fi

# If the current device name already contains a hyphen,
# rename it using the pre-existing prefix and the final six characters of the serial number,
# exiting if the name is already correct.
elif [[ $currentName == *"-"* ]];
then
    echo "Log: $(date "+%F %T") Device name contains a prefix." | tee -a "$logPath"
    prefix=$(echo "$currentName" | sed 's/\(.*-\).*/\1/')
    newName="${prefix}${serialShort}"
    if [[ $currentName == $newName ]];
    then
        echo "Log: $(date "+%F %T") Device already named correctly, \"$currentName\"." | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Exiting." | tee -a "$logPath"
    else
        echo "Log: $(date "+%F %T") Current computer name contains a hyphen, \"$currentName\" with prefix \"$prefix\"." | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Renaming to \"$newName\"." | tee -a "$logPath"
        rename_Device "$newName"
    fi

# If the current device name fails to match any conditions,
# rename it using the SLU standard.
else
    echo "Log: $(date "+%F %T") Current computer name matches no critera, \"$currentName\"." | tee -a "$logPath"
    echo "Log: $(date "+%F %T") Renaming to \"$standardName\"." | tee -a "$logPath"
    rename_Device "$standardName"
fi

exit 0

