#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 11-12-25  ###
### Updated: 11-12-25  ###
### Version: 1.0       ###
##########################

readonly logFile='/var/log/computerRename_Background.log'
readonly dialogTitle='Computer Rename: Custom'
readonly SLUIconFile='/usr/local/jamfconnect/SLU.icns'
readonly genericIconFile='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
activeIcon="$SLUIconFile"

# Append current status to log file
function log_Message() {
    local message="$1"
    local type="${2:-Log}"
    local timestamp="$(date "+%F %T")"
    if [[ -w "$logFile" ]];
    then
        printf "%s: %s %s\n" "$type" "$timestamp" "$message" | tee -a "$logFile"
    else
        printf "%s: %s %s\n" "$type" "$timestamp" "$message"
    fi
}

# Check for valid icon file, AppleScript dialog boxes will error without it
function icon_Check() {
    if [[ ! -f "$activeIcon" ]];
    then
        log_Message "No SLU icon found" "WARN"
        if [[ -f '/usr/local/bin/jamf' ]];
        then
            log_Message "Attempting icon install via Jamf"
            /usr/local/bin/jamf policy -event SLUFonts
        else
            log_Message "No Jamf binary found" "WARN"
        fi
        if [[ ! -f "$activeIcon" ]];
        then
            if [[ -f "$genericIconFile" ]];
            then
                log_Message "Generic icon found"
                activeIcon="$genericIconFile"
            else
                log_Message "Generic icon not found" "ERROR"
                return 1
            fi
        fi
    else
        log_Message "SLU icon found"
    fi
    return 0
}

# Contains scutil commands to change device name
function rename_Device() {
    local name="$1"
    if [[ -n "$name" ]];
    then
        log_Message "Renaming device to: $name"
        /usr/sbin/scutil --set ComputerName "$name"
        /usr/sbin/scutil --set LocalHostName "$name"
        /usr/sbin/scutil --set HostName "$name"
        /usr/local/bin/jamf recon
        return 0
    else
        log_Message "Name is empty" "ERROR"
        return 1
    fi
}

# AppleScript - Text field dialog prompt for inputting information
function textField_Dialog() {
    local promptString="$1"
    local dialogType="$2"
    local count=1
    while [ $count -le 10 ];
    do
        textFieldDialog=$(/usr/bin/osascript <<OOP
        try
            set promptString to "$promptString"
            set iconFile to "$activeIcon"
            set dialogTitle to "$dialogTitle"
            set dialogType to "$dialogType"
            if dialogType is "hidden" then
                set dialogResult to display dialog promptString buttons {"Cancel", "OK"} default button "OK" with hidden answer default answer "" with icon POSIX file iconFile with title dialogTitle giving up after 900
            else
                set dialogResult to display dialog promptString buttons {"Cancel", "OK"} default button "OK" with answer default answer "" with icon POSIX file iconFile with title dialogTitle giving up after 900
            end if
            set buttonChoice to button returned of dialogResult
            if buttonChoice is equal to "OK" then
                return text returned of dialogResult
            else
                return "timeout"
            end if
        on error
            return "Cancel"
        end try
OOP
        )
        case "$textFieldDialog" in
            'Cancel')
                log_Message "User responded with: $textFieldDialog"
                return 1
                ;;
            'timeout')
                log_Message "No response, re-prompting ($count/10)" "WARN"
                ((count++))
                ;;
            '')
                log_Message "Nothing entered in text field" "WARN"
                alert_Dialog "Please enter something or select cancel."
                ;;
            *)
                if [[ "$dialogType" == 'hidden' ]];
                then
                    log_Message "Continued"
                else
                    log_Message "User responded with: $textFieldDialog"
                fi
                return 0
                ;;
        esac
    done
    return 1
}

# AppleScript - Create alert dialog window
function alert_Dialog() {
    local alertTitle="$1"
    local alertMessage="$2"
    log_Message "Displaying alert dialog"
    alertDialog=$(/usr/bin/osascript <<OOP
    try
        set alertTitle to "$alertTitle"
        set alertMessage to "$alertMessage"
        set choice to (display alert alertTitle message alertMessage as critical buttons "OK" default button 1 giving up after 900)
        if (gave up of choice) is true then
            return "TIMEOUT"
        else
            return (button returned of choice)
        end if
    on error
        return "ERROR"
    end try
OOP
    )
    case "$alertDialog" in
        'ERROR')
            log_Message "Unable to show alert dialog" "ERROR"
            ;;
        'TIMEOUT')
            log_Message "Alert timed out" "WARN"
            ;;
        *)
            log_Message "Continued through alert dialog"
            ;;
    esac
}

function main() {
    if [[ -w "$logFile" ]];
    then
        printf "Log: $(date "+%F %T") Beginning Computer Rename Custom script\n" | tee "$logFile"
    else
        printf "Log: $(date "+%F %T") Beginning Computer Rename Custom script\n"
    fi

    if ! icon_Check;
    then
        log_Message "Exiting at icon check" "ERROR"
        exit 1
    fi

    if ! textField_Dialog "Enter your custom computer name:";
    then
        log_Message "Exiting at textfield dialog"
        exit 0
    fi

    if ! rename_Device "$textFieldDialog";
    then
        log_Message "Exiting at device rename" "ERROR"
        exit 1
    fi

    exit 0
}

main

