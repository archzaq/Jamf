#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 1-30-25   ###
### Updated: 2-25-25   ###
### Version: 1.6       ###
##########################

readonly dateAtStart="$(date "+%F_%H-%M-%S")"
readonly userAccount="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly homePath="/Users/${userAccount}"
readonly cloudPath="${homePath}/Library/CloudStorage"
readonly foundFilesPath="${homePath}/Desktop/${dateAtStart}_fileSearch.log"
readonly iconPath='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/'
readonly finderIconPath="${iconPath}/FinderIcon.icns"
readonly dialogTitle='File Search'
readonly logPath='/var/log/fileSearch.log'

# AppleScript - Ask user for search filter
function first_Dialog() {
    while true;
    do
        firstDialog=$(/usr/bin/osascript <<OOP
        try
            set prompt to "Welcome to File Search!\n\nPlease enter the text you would like to search for:"
            set dialogResult to display dialog prompt buttons {"Cancel", "Continue"} default answer "" default button "Continue" \
                with title "$dialogTitle" with icon POSIX file "$finderIconPath" giving up after 900
            set buttonChoice to button returned of dialogResult
            set typedText to text returned of dialogResult
            if buttonChoice is equal to "Continue" then
                return typedText
            else
                return buttonChoice
            end if
        on error
            return "cancelled"
        end try
OOP
        )
        case "$firstDialog" in
            'cancelled')
                echo "Log: $(date "+%F %T") User selected cancel" | tee -a "$logPath"
                return 1
                ;;
            '')
                echo "Log: $(date "+%F %T") No response, re-prompting" | tee -a "$logPath"
                ;;
            *)
                echo "Log: $(date "+%F %T") User responded with: $firstDialog" | tee -a "$logPath"
                return 0
                ;;
        esac
    done
}

# AppleScript - Ask user for search location
function dropdown_Prompt() {
    while true;
    do
        dropdownPrompt=$(/usr/bin/osascript <<OOP
        set options to {"Quick Scan", "Home Scan - $homePath", "Deep Scan - Entire Drive", "Custom Scan"}
        set userChoice to (choose from list options with prompt "Please choose the depth for which to search:" default items "Quick Scan" with title "$dialogTitle")
        if userChoice is false then
            return "cancelled"
        else if userChoice is {} then
            return "timeout"
        else
            return (item 1 of userChoice)
        end if
OOP
        )
        case "$dropdownPrompt" in
            'cancelled')
                echo "Log: $(date "+%F %T") User selected cancel" | tee -a "$logPath"
                return 1
                ;;
            'timeout')
                echo "Log: $(date "+%F %T") Timed out, re-prompting" | tee -a "$logPath"
                ;;
            *)
                echo "Log: $(date "+%F %T") User chose: $dropdownPrompt" | tee -a "$logPath"
                return 0
                ;;
        esac
    done
}

# AppleScript - Ask user for custom search location
function customSearch_FolderChoice() {
    while true;
    do
        customDialogPath=$(/usr/bin/osascript <<OOP
        try
            set selectedFolder to (choose folder with prompt "Select a folder to search within:")
            set folderPath to POSIX path of selectedFolder
            return folderPath
        on error
            return "cancelled"
        end try
OOP
        )
        case "$customDialogPath" in
            'cancelled')
                echo "Log: $(date "+%F %T") User selected cancel" | tee -a "$logPath"
                return 1
                ;;
            '')
                echo "Log: $(date "+%F %T") No response, re-prompting" | tee -a "$logPath"
                ;;
            *)
                echo "Log: $(date "+%F %T") User chose: $customDialogPath" | tee -a "$logPath"
                return 0
                ;;
        esac
    done
}

# Search a custom path folder for the search filter, excluding library for a quick search
function custom_Search() {
    local path="$1"
    if [[ -d "$path" ]];
    then
        echo "Log: $(date "+%F %T") Beginning search at $path for: $firstDialog" | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Searching for files at $path for: $firstDialog" >> "$foundFilesPath"
        if [ "$quickSearchActivated" -eq 0 ];
        then
            find "$path" -type f -name "*${firstDialog}*" 2>/dev/null >> "$foundFilesPath"
        else
            find "$path" -path "$path/Library" -prune -false -o -type f -name "*${firstDialog}*" 2>/dev/null >> "$foundFilesPath"
        fi
        echo "Log: $(date "+%F %T") Completed search at $path" | tee -a "$logPath"
        return 0
    else
        return 1
    fi
}

# Search within specified file types for the search filter, excluding library for a quick search 
function within_Files() {
    local path="$1"
    if [[ -d "$path" ]];
    then
        echo "Log: $(date "+%F %T") Beginning search within files at $path for: $firstDialog" | tee -a "$logPath"
        echo "Log: $(date "+%F %T") Searching within files at $path for: $firstDialog" >> "$foundFilesPath"
        if [ "$quickSearchActivated" -eq 0 ];
        then
            find "$path" -type f \
                \( -name "*.sh" -o -name "*.txt" -o -name "*.py" -o -name "*.plist" -o -name "*.csv" \) \
                -exec grep -l "$firstDialog" {} \; 2>/dev/null >> "$foundFilesPath"
        else
            find "$path" -path "/Users/$userAccount/Library" -prune -o -type f \
                \( -name "*.sh" -o -name "*.txt" -o -name "*.py" -o -name "*.plist" -o -name "*.csv" \) \
                -exec grep -l "$firstDialog" {} \; 2>/dev/null >> "$foundFilesPath"
        fi
        echo "Log: $(date "+%F %T") Completed search within files at $path" | tee -a "$logPath"
        return 0
    else
        return 1
    fi
}

# Check the script is ran with admin privileges
function sudo_Check() {
    if [ "$(id -u)" -ne 0 ];
    then
        echo "Please run this script as root or using sudo!"
        exit 1
    fi
}

# To help exit nicely
function exit_Nicely() {
    local exitCode=$?
    if [ $exitCode -ne 0 ];
    then
        echo "Log: $(date "+%F %T") Script interrupted or terminated" | tee -a "$logPath"
        if [[ -f "$foundFilesPath" ]];
        then
            echo "Log: $(date "+%F %T") Search incomplete - script interrupted" >> "$foundFilesPath"
            open "$foundFilesPath"
        fi
        echo "Log: $(date "+%F %T") Exiting with code: $exitCode" | tee -a "$logPath"
        exit $exitCode
    else
        open "$foundFilesPath"
        echo "Log: $(date "+%F %T") Exiting successfully" | tee -a "$logPath"
    fi
}

function main() {
    sudo_Check
    if [ ! -d "$iconPath" ];
    then
        echo "Log: $(date "+%F %T") Missing icon for AppleScript prompt, exiting" | tee "$logPath"
        exit 1
    fi

    echo "Log: $(date "+%F %T") Beginning File Search log" | tee "$logPath"
    while true;
    do
        echo "Log: $(date "+%F %T") Displaying first dialog" | tee -a "$logPath"
        if ! first_Dialog;
        then
            echo "Log: $(date "+%F %T") Exiting at first dialog" | tee -a "$logPath"
            exit 0
        fi
        
        local scanComplete=0
        local returnToFirstDialog=0
        while [ $scanComplete -eq 0 ] && [ $returnToFirstDialog -eq 0 ];
        do
            quickSearchActivated=0
            echo "Log: $(date "+%F %T") Displaying drop-down prompt" | tee -a "$logPath"
            if ! dropdown_Prompt;
            then
                echo "Log: $(date "+%F %T") Going back to first dialog" | tee -a "$logPath"
                returnToFirstDialog=1
            else
                if [ ! -f "$foundFilesPath" ];
                then
                    touch "$foundFilesPath"
                fi
                
                case "$dropdownPrompt" in
                    'Quick Scan')
                        quickSearchActivated=1
                        if ! custom_Search "$homePath";
                        then
                            echo "Log: $(date "+%F %T") Exiting at home search for invalid path" | tee -a "$logPath"
                            exit 1
                        fi
                        if ! within_Files "$homePath";
                        then
                            echo "Log: $(date "+%F %T") Invalid path for searching within files" | tee -a "$logPath"
                            exit 1
                        fi
                        scanComplete=1
                        ;;
                        
                    'Home Scan -'*)
                        if ! custom_Search "$homePath";
                        then
                            echo "Log: $(date "+%F %T") Invalid path for searching files" | tee -a "$logPath"
                            exit 1
                        fi
                        if ! within_Files "$homePath";
                        then
                            echo "Log: $(date "+%F %T") Invalid path for searching within files" | tee -a "$logPath"
                            exit 1
                        fi
                        scanComplete=1
                        ;;
                        
                    'Deep Scan - Entire Drive')
                        if ! custom_Search "/";
                        then
                            echo "Log: $(date "+%F %T") Invalid path for searching files" | tee -a "$logPath"
                            exit 1
                        fi
                        if ! within_Files "/";
                        then
                            echo "Log: $(date "+%F %T") Invalid path for searching within files" | tee -a "$logPath"
                            exit 1
                        fi
                        scanComplete=1
                        ;;
                        
                    'Custom Scan')
                        echo "Log: $(date "+%F %T") Displaying custom search dialog" | tee -a "$logPath"
                        if ! customSearch_FolderChoice;
                        then
                            echo "Log: $(date "+%F %T") Going back to drop-down prompt" | tee -a "$logPath"
                        else
                            if ! custom_Search "$customDialogPath";
                            then
                                echo "Log: $(date "+%F %T") Invalid path for searching files" | tee -a "$logPath"
                                exit 1
                            fi
                            if ! within_Files "$customDialogPath";
                            then
                                echo "Log: $(date "+%F %T") Invalid path for searching within files" | tee -a "$logPath"
                                exit 1
                            fi
                            scanComplete=1
                        fi
                        ;;
                esac
            fi
        done

        if [ $scanComplete -eq 1 ];
        then
            echo "Log: $(date "+%F %T") Found file logs can be found at $foundFilesPath" | tee -a "$logPath"
            exit 0
        fi
    done
}

# Just using trap to catch interrupts
trap exit_Nicely EXIT
trap 'exit' INT TERM HUP

main

