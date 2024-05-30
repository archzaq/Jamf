#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

# Uninstall Adobe Acrobat function
function uninstall_Acrobat(){
    echo "Uninstalling Adobe Acrobat..."
    sudo rm -rf "/Applications/Adobe Acrobat"*
    sudo rm -rf "/Library/Application Support/Adobe/Acrobat"*
    sudo rm -rf "/Library/Internet Plug-Ins/Adobe"*
    sudo rm -rf "/Applications/Utilities/Adobe Sync"
    sudo rm -rf "/Applications/Utilities/Adobe Application"
    sudo rm -rf "/Applications/Utilities/Adobe Installers"
    sudo rm -rf "/Applications/Utilities/Adobe Application Manager"
    sudo rm -rf "/Applications/Utilities/Adobe Genuine Service"
    echo "Uninstalled Adobe Acrobat."
}

# Uninstall Adobe Reader function
function uninstall_Reader(){
    echo "Uninstalling Adobe Reader..."
    sudo rm -rf "/Applications/Adobe Reader"*
    sudo rm -rf "/Library/Application Support/Adobe/Adobe Reader"*
    sudo rm -rf "/Library/Internet Plug-Ins/Adobe"*
    sudo rm -rf "/Applications/Utilities/Adobe Sync"
    sudo rm -rf "/Applications/Utilities/Adobe Application"
    sudo rm -rf "/Applications/Utilities/Adobe Installers"
    sudo rm -rf "/Applications/Utilities/Adobe Application Manager"
    sudo rm -rf "/Applications/Utilities/Adobe Genuine Service"
    echo "Uninstalled Adobe Reader."
}

# Uninstall Creative Cloud function
function uninstall_CC(){
    echo "Uninstalling Adobe Creative Cloud..."
    sudo rm -rf "/Applications/Adobe Creative Cloud"*
    sudo rm -rf "/Library/Application Support/Adobe/Creative Cloud"*
    sudo rm -rf "/Applications/Utilities/Adobe Creative Cloud"
    sudo rm -rf "/Applications/Utilities/Adobe Creative Cloud Experience"
    echo "Uninstalled Adobe Creative Cloud."
}

# Check for any process running related to Adobe Acrobat or Adobe Reader and kill the process
function kill_App(){
    if pgrep -f "$1" >/dev/null;
    then
        pkill -f "$1"
        echo "$1 process killed"
    fi
}

# Check for any process running related to Adobe Creative Cloud and kill the process
function kill_CC() {
    if pgrep -f "Creative Cloud" >/dev/null;
    then
        pkill -f "Creative Cloud"
        echo "Adobe Creative Cloud process killed"
    fi
}

kill_App "Adobe Acrobat"    # Check for any process running related to Adobe Acrobat and kill the process
kill_App "Adobe Reader"     # Check for any process running related to Adobe Reader and kill the process
kill_CC                     # Check for any process running related to Adobe Creative Cloud and kill the process

# Search for Adobe Acrobat, Adobe Reader, and Adobe Creative Cloud folders
echo "Searching for Adobe applications..."
for app in "/Applications/"* "/Applications/Utilities/"*;
do
    if [[ "$app" == *"Adobe Acrobat"* ]] && [ ! "$uninstallAcrobat" ];
    then
        echo "Adobe Acrobat folder found: $app"
        uninstall_Acrobat
        uninstallAcrobat=true
    elif [[ "$app" == *"Adobe Reader"* ]] && [ ! "$uninstallReader" ];
    then
        echo "Adobe Reader folder found: $app"
        uninstall_Reader
        uninstallReader=true
    elif [[ "$app" == *"Adobe Creative Cloud"* ]] && [ ! "$uninstallCC" ];
    then
        echo "Adobe Creative Cloud folder found: $app"
        uninstall_CC
        uninstallCC=true
    fi
done

# Iterate through all installed pkgs, removing those related to Adobe Acrobat or Adobe Reader
echo "Searching for Adobe Acrobat or Adobe Reader pkg installations..."
while read -r package;
do
    if [[ $package == *"adobe.acrobat"* ]];
    then
        echo "Uninstalling $package..."
        sudo pkgutil --forget "$package"
    elif [[ $package == *"adobe.reader"* ]];
    then
        echo "Uninstalling $package..."
        sudo pkgutil --forget "$package"
    fi
done < <(pkgutil --pkgs)

echo "Uninstall complete."
exit 0