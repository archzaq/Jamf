#!/bin/bash

# Rename Computer 
# Version 2
# Zac Reeves

# Variables
computerSerial=$(ioreg -l | grep IOPlatformSerialNumber | sed 's/"$//' | sed 's/.*"//')
computerSerialShort=${computerSerial: -6}
computerName="SLU-$computerSerialShort"

currentName=$(hostname)

if [[ $currentName == *"-"* ]];
then
    echo "Computer already contains hyphen. $currentName"
    exit 0
fi

# Commands
/usr/sbin/scutil --set ComputerName $computerName
/usr/sbin/scutil --set LocalHostName $computerName
/usr/sbin/scutil --set HostName $computerName

/usr/local/bin/jamf recon
