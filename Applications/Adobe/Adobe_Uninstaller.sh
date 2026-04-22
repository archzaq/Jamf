#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 05-29-24   ###
###  Updated: 04-22-26   ###
###  Version: 1.5        ###
############################

readonly scriptName='uninstall_Adobe'
readonly logFile="/var/log/${scriptName}.log"
readonly maxAttempts=10
readonly dialogTitle='SLU ITS - Adobe Uninstall'
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

# Ensure running as root
function check_Sudo() {
    if [[ $(id -u) -ne 0 ]];
    then
        log_Message "Script must be run as root (current UID: $(id -u))" "ERROR"
        return 1
    fi
    log_Message "Running as root"
    return 0
}

# Check for valid icon file, AppleScript dialog boxes will error without it
function check_Icon() {
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

# Detect whether a product is installed via Spotlight (diagnostic only)
function detect_Installed() {
    local productLabel="$1"
    shift
    local bundleID path foundSomething=0

    for bundleID in "$@";
    do
        while IFS= read -r path;
        do
            [[ -n "$path" && -e "$path" ]] || continue
            log_Message "Detected ${productLabel} at: $path"
            foundSomething=1
        done < <(/usr/bin/mdfind "kMDItemCFBundleIdentifier == '$bundleID'" 2>/dev/null)
    done

    if [[ $foundSomething -eq 0 ]];
    then
        log_Message "No ${productLabel} installs detected by Spotlight"
    fi
}

# Remove a path with a log line if it exists
function remove_IfExists() {
    local target="$1"
    if [[ -e "$target" ]];
    then
        log_Message "Removing: $target"
        rm -rf "$target"
    fi
}

# Remove shared Adobe support files (both Acrobat and Reader drop these)
function remove_SharedAdobeSupport() {
    local sharedPaths=(
        "/Library/Application Support/Adobe/Acrobat"*
        "/Library/Internet Plug-Ins/Adobe"*
        "/Applications/Utilities/Adobe Sync"
        "/Applications/Utilities/Adobe Application"
        "/Applications/Utilities/Adobe Installers"
        "/Applications/Utilities/Adobe Application Manager"
        "/Applications/Utilities/Adobe Genuine Service"
    )
    local path
    for path in "${sharedPaths[@]}";
    do
        remove_IfExists "$path"
    done
}

# Uninstall Adobe Acrobat
function uninstall_Acrobat() {
    detect_Installed "Adobe Acrobat" 'com.adobe.Acrobat.Pro' 'com.adobe.Acrobat' 'com.adobe.Acrobat.reader'
    local acrobatPaths=(
        "/Applications/Adobe Acrobat"*
    )
    local path
    for path in "${acrobatPaths[@]}";
    do
        remove_IfExists "$path"
    done
    remove_SharedAdobeSupport
    log_Message "Uninstalled Adobe Acrobat"
}

# Uninstall Adobe Reader
function uninstall_Reader() {
    detect_Installed "Adobe Reader" 'com.adobe.Reader' 'com.adobe.AdobeReader'
    local readerPaths=(
        "/Applications/Adobe Reader"*
        "/Library/Application Support/Adobe/Adobe Reader"*
    )
    local path
    for path in "${readerPaths[@]}";
    do
        remove_IfExists "$path"
    done
    remove_SharedAdobeSupport
    log_Message "Uninstalled Adobe Reader"
}

# Uninstall Creative Cloud
function uninstall_CC() {
    detect_Installed "Adobe Creative Cloud" 'com.adobe.acc.AdobeCreativeCloud' 'com.adobe.CCXProcess' 'com.adobe.accmac'
    local ccPaths=(
        "/Applications/Adobe Creative Cloud"*
        "/Applications/Utilities/Adobe Creative Cloud"*
        "/Library/Application Support/Adobe/Creative Cloud"*
        "/Applications/Utilities/Adobe Creative Cloud Experience"
    )
    local path
    for path in "${ccPaths[@]}";
    do
        remove_IfExists "$path"
    done
    log_Message "Uninstalled Adobe Creative Cloud"
}

# AppleScript - Informing the user and giving them two choices
function binary_Dialog() {
    local promptString="$1"
    local mainButton="$2"
    local count=1
    while [ $count -le $maxAttempts ];
    do
        binDialog=$(/usr/bin/osascript <<OOP
        try
            set promptString to "$promptString"
            set mainButton to "$mainButton"
            set iconPath to "$activeIcon"
            set dialogTitle to "$dialogTitle"
            set dialogResult to display dialog promptString buttons {"Cancel", mainButton} default button mainButton with icon POSIX file iconPath with title dialogTitle giving up after 900
            set buttonChoice to button returned of dialogResult
            if buttonChoice is equal to "" then
                return "TIMEOUT"
            else
                return buttonChoice
            end if
        on error
            return "CANCEL"
        end try
OOP
        )
        case "$binDialog" in
            'CANCEL' | 'Cancel')
                log_Message "User responded with: \"$binDialog\""
                return 1
                ;;
            'TIMEOUT' | '')
                log_Message "No response, re-prompting ($count/$maxAttempts)"
                ((count++))
                sleep 1
                ;;
            *)
                log_Message "User responded with: \"$binDialog\""
                return 0
                ;;
        esac
    done
    return 1
}

# Prompt once up front before doing anything destructive
function prompt_UserConsent() {
    local promptText='All Adobe applications will be closed. Adobe Acrobat, Reader, and Creative Cloud will be uninstalled.\n\nSelect \"Continue\" to begin.\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000.'
    if binary_Dialog "$promptText" "Continue";
    then
        log_Message "User consented to uninstall"
        return 0
    else
        return 1
    fi
}

# Kill a running app by name
function kill_App() {
    local name="$1"
    if pgrep -f "$name" >/dev/null;
    then
        pkill -f "$name"
        log_Message "$name process killed"
    else
        log_Message "Unable to locate ${name} process"
    fi
}

function main() {
    printf "Log: $(date "+%F %T") Beginning ${scriptName} script\n" | tee "$logFile"

    check_Sudo || exit 1
    check_Icon || exit 1

    # Ask once up front
    if ! prompt_UserConsent;
    then
        log_Message "User cancelled at first dialog. No changes made" "INFO"
        exit 1
    fi

    # Kill running Adobe processes
    kill_App "Adobe Acrobat"
    kill_App "Adobe Reader"
    kill_App "Creative Cloud"

    # Uninstall each product
    log_Message "Searching for and removing Adobe applications"
    uninstall_Acrobat
    uninstall_Reader
    uninstall_CC

    # Forget pkg receipts for Acrobat and Reader
    log_Message "Searching for Adobe Acrobat or Adobe Reader pkg receipts"
    while read -r package;
    do
        if [[ $package == *"adobe.acrobat"* || $package == *"adobe.reader"* ]];
        then
            log_Message "Forgetting receipt: $package"
            pkgutil --forget "$package"
        fi
    done < <(pkgutil --pkgs)

    log_Message "Uninstall complete"
    exit 0
}

main
