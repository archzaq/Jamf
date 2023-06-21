#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

echo "Searching for Adobe installations..."

# Iterate through all installed packages
while read -r package; do
    if [[ $package == *"acrobat"* ]];
    then
        # Check for any process running named Adobe, if running, kill the app
        if pgrep "Adobe" >/dev/null;
        then
            pkill "Adobe"
            echo "Adobe process killed"
        else
            echo "Adobe not running"
        fi
        echo "Uninstalling $package..."
        sudo pkgutil --forget "$package"

        # Uninstall Adobe Acrobat, Acrobat DC, and/or Acrobat Pro
        echo "Uninstalling Adobe Acrobat, Acrobat DC, and/or Acrobat Pro..."
        sudo rm -rf "/Applications/Adobe Acrobat"*
        sudo rm -rf "/Library/Application Support/Adobe/Acrobat"*
        sudo rm -rf "/Library/Internet Plug-Ins/Adobe"*
        echo "Uninstall complete."
        exit 0

    elif [[ $package == *"reader"* ]];
    then
        # Check for any process running named Adobe, if running, kill the app
        if pgrep "Adobe" >/dev/null;
        then
            pkill "Adobe"
            echo "Adobe process killed"
        else
            echo "Adobe not running"
        fi
        echo "Uninstalling $package..."
        sudo pkgutil --forget "$package"

        # Uninstall Adobe Reader or Adobe Reader DC
        echo "Uninstalling Adobe Reader and/or Adobe Reader DC..."
        sudo rm -rf "/Applications/Adobe Reader"*
        sudo rm -rf "/Library/Application Support/Adobe/Adobe Reader"*
        sudo rm -rf "/Library/Internet Plug-Ins/Adobe"*
        echo "Uninstall complete."
        exit 0
    fi
done < <(pkgutil --pkgs)

echo "pkgutil unable to locate any Acrobat or Reader packages."
echo "Exiting..."
exit 0
