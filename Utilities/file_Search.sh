#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 01-30-25  ###
### Updated: 07-25-25  ###
### Version: 1.11      ###
##########################

readonly dateAtStart="$(date "+%F_%H-%M-%S")"
readonly userAccount="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly homePath="/Users/${userAccount}"
readonly cloudPath="${homePath}/Library/CloudStorage"
readonly foundFilesPath="${homePath}/Desktop/${dateAtStart}_fileSearch.log"
readonly iconPath='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/'
readonly finderIconPath="${iconPath}/FinderIcon.icns"
readonly dialogTitle='File Search'
readonly logFile='/var/log/file_Search.log'
quickSearchActivated=0
fileCount=0
declare -a foundFilesArray=()

# Append current status to log file
function log_Message() {
    local timestamp="$(date "+%F %T")"
    printf "Log: %s %s\n" "$timestamp" "$1" | tee -a "$logFile"
}

# AppleScript - Ask user for search filter
function first_Dialog() {
    while true;
    do
        firstDialog=$(/usr/bin/osascript <<OOP
        tell application "System Events"
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
        end tell
OOP
        )
        case "$firstDialog" in
            'cancelled')
                log_Message "User selected cancel"
                return 1
                ;;
            '')
                log_Message "No response, re-prompting"
                ;;
            *)
                log_Message "User responded with: $firstDialog"
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
        tell application "System Events"
            set options to {"Quick Scan", "Home Scan - $homePath", "Deep Scan - Entire Drive", "Custom Scan"}
            set userChoice to (choose from list options with prompt "Please choose the depth for which to search:" default items "Quick Scan" with title "$dialogTitle")
        end tell
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
                log_Message "User selected cancel"
                return 1
                ;;
            'timeout')
                log_Message "Timed out, re-prompting"
                ;;
            *)
                log_Message "User chose: $dropdownPrompt"
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
        tell application "System Events"
            try
                set selectedFolder to (choose folder with prompt "Select a folder to search within:")
                set folderPath to POSIX path of selectedFolder
                return folderPath
            on error
                return "cancelled"
            end try
        end tell
OOP
        )
        case "$customDialogPath" in
            'cancelled')
                log_Message "User selected cancel"
                return 1
                ;;
            '')
                log_Message "No response, re-prompting"
                ;;
            *)
                log_Message "User chose: $customDialogPath"
                return 0
                ;;
        esac
    done
}

# AppleScript - Display found files in dropdown
function display_FoundFiles() {
    local filesList=""
    for file in "${foundFilesArray[@]}";
    do
        filesList="${filesList}\"${file}\","
    done
    filesList="${filesList%,}"
    
    selectedFile=$(/usr/bin/osascript <<OOP
    tell application "System Events"
        set fileOptions to {${filesList}}
        set prompt to "Found ${fileCount} file(s) for $firstDialog. Select a file to open it:"
        set userChoice to (choose from list fileOptions with prompt prompt with title "$dialogTitle" OK button name "Open" cancel button name "Done")
        if userChoice is false then
            return "done"
        else
            return (item 1 of userChoice)
        end if
    end tell
OOP
    )
    
    if [[ "$selectedFile" != "done" ]] && [[ -n "$selectedFile" ]];
    then
        log_Message "User selected file: $selectedFile"
        open "$selectedFile"
        return 0
    else
        log_Message "User closed file selection dialog"
        return 1
    fi
}

# Search a custom path folder for the search filter, excluding library for a quick search
function search_Files() {
    local path="$1"
    local tempFile=$(/usr/bin/mktemp)
    local searchCount=0
    if [[ -d "$path" ]];
    then
        log_Message "Beginning search at $path for: $firstDialog"
        log_Message "Searching for files at $path for: $firstDialog" >> "$foundFilesPath"
        if [ "$quickSearchActivated" -eq 0 ];
        then
            find "$path" -type f -name "*${firstDialog}*" 2>/dev/null | sort -r | tee "$tempFile" >> "$foundFilesPath"
        else
            find "$path" -path "$path/Library" -prune -false -o -type f -name "*${firstDialog}*" 2>/dev/null | sort -r | tee "$tempFile" >> "$foundFilesPath"
        fi

        while IFS= read -r line;
        do
            foundFilesArray+=("$line")
        done < "$tempFile"

        searchCount=$(wc -l < "$tempFile")
        fileCount=$((fileCount + searchCount))
        rm -f "$tempFile"

        log_Message "Completed search at $path"
        return 0
    else
        return 1
    fi
}

# Search within specified file types for the search filter, excluding library for a quick search 
function within_Files() {
    local path="$1"
    local tempFile=$(/usr/bin/mktemp)
    local searchCount=0
    if [[ -d "$path" ]];
    then
        log_Message "Beginning search within files at $path for: $firstDialog"
        log_Message "Searching within files at $path for: $firstDialog" >> "$foundFilesPath"
        if [ "$quickSearchActivated" -eq 0 ];
        then
            find "$path" -type f \
                \( -name "*.sh" -o -name "*.txt" -o -name "*.py" -o -name "*.plist" -o -name "*.csv" \) \
                -exec grep -l "$firstDialog" {} \; 2>/dev/null | sort -r | tee "$tempFile" >> "$foundFilesPath"
        else
            find "$path" -path "/Users/$userAccount/Library" -prune -o -type f \
                \( -name "*.sh" -o -name "*.txt" -o -name "*.py" -o -name "*.plist" -o -name "*.csv" \) \
                -exec grep -l "$firstDialog" {} \; 2>/dev/null | sort -r | tee "$tempFile" >> "$foundFilesPath"
        fi

        while IFS= read -r line;
        do
            foundFilesArray+=("$line")
        done < "$tempFile"

        searchCount=$(wc -l < "$tempFile")
        fileCount=$((fileCount + searchCount))
        rm -f "$tempFile"

        log_Message "Completed search within files at $path"
        return 0
    else
        return 1
    fi
}

# Check the script is ran with admin privileges
function sudo_Check() {
    if [ "$(id -u)" -ne 0 ];
    then
        printf "Please run this script as root or using sudo!\n"
        exit 1
    fi
}

# To help exit nicely
function exit_Nicely() {
    local exitCode=$?
    if [ $exitCode -ne 0 ];
    then
        log_Message "Script interrupted or terminated"
        if [[ -f "$foundFilesPath" ]];
        then
            log_Message "Search incomplete - script interrupted" >> "$foundFilesPath"
            open "$foundFilesPath"
        fi
        log_Message "Exiting with code: $exitCode"
        exit $exitCode
    else
        log_Message "Exiting successfully"
    fi
}

function main() {
    sudo_Check
    printf "Log: $(date "+%F %T") Beginning File Search script\n" | tee "$logFile"

    if [ ! -d "$iconPath" ];
    then
        log_Message "Missing icon for AppleScript prompt, exiting"
        exit 1
    fi

    while true;
    do
        fileCount=0
        foundFilesArray=()
        log_Message "Displaying first dialog"
        if ! first_Dialog;
        then
            log_Message "Exiting at first dialog"
            exit 0
        fi
        
        local scanComplete=0
        local returnToFirstDialog=0
        while [ $scanComplete -eq 0 ] && [ $returnToFirstDialog -eq 0 ];
        do
            quickSearchActivated=0
            log_Message "Displaying drop-down prompt"
            if ! dropdown_Prompt;
            then
                log_Message "Going back to first dialog"
                returnToFirstDialog=1
            else
                if [ ! -f "$foundFilesPath" ];
                then
                    touch "$foundFilesPath"
                fi
                
                case "$dropdownPrompt" in
                    'Quick Scan')
                        quickSearchActivated=1
                        if ! search_Files "$homePath";
                        then
                            log_Message "Exiting at home search for invalid path"
                            exit 1
                        fi
                        if ! within_Files "$homePath";
                        then
                            log_Message "Invalid path for searching within files"
                            exit 1
                        fi
                        scanComplete=1
                        ;;
                        
                    'Home Scan -'*)
                        if ! search_Files "$homePath";
                        then
                            log_Message "Invalid path for searching files"
                            exit 1
                        fi
                        if ! within_Files "$homePath";
                        then
                            log_Message "Invalid path for searching within files"
                            exit 1
                        fi
                        scanComplete=1
                        ;;
                        
                    'Deep Scan - Entire Drive')
                        if ! search_Files "/";
                        then
                            log_Message "Invalid path for searching files"
                            exit 1
                        fi
                        if ! within_Files "/";
                        then
                            log_Message "Invalid path for searching within files"
                            exit 1
                        fi
                        scanComplete=1
                        ;;
                        
                    'Custom Scan')
                        log_Message "Displaying custom search dialog"
                        if ! customSearch_FolderChoice;
                        then
                            log_Message "Going back to drop-down prompt"
                        else
                            if ! search_Files "$customDialogPath";
                            then
                                log_Message "Invalid path for searching files"
                                exit 1
                            fi
                            if ! within_Files "$customDialogPath";
                            then
                                log_Message "Invalid path for searching within files"
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
            if [ $fileCount -lt 1 ];
            then
                log_Message "No files found"
                if [[ -f "$foundFilesPath" ]];
                then
                    rm -f "$foundFilesPath"
                fi
                /usr/bin/osascript -e 'display dialog "No files found matching '"$firstDialog"'" buttons {"OK"} default button "OK" with title "'"$dialogTitle"'" with icon POSIX file "'"$finderIconPath"'"' >/dev/null
            else
                log_Message "Found $fileCount files"
                log_Message "Found file logs can be found at $foundFilesPath"
                
                while true;
                do
                    if ! display_FoundFiles;
                    then
                        break
                    fi
                done
            fi

            exit 0
        fi
    done
}

# Just using trap to catch interrupts
trap exit_Nicely EXIT
trap 'exit' INT TERM HUP

main
