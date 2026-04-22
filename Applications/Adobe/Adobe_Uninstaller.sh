#!/bin/bash

############################
###  Author:  Zac Reeves ###
###  Created: 00-00-00   ###
###  Updated: 04-22-26   ###
###  Version: 0.2        ###
############################

readonly scriptName='uninstall_Adobe'
readonly logFile="/var/log/${scriptName}.log"
readonly maxAttempts=10
readonly dialogTitle='SLU ITS - Adobe Uninstall'
readonly SLUIconFile='/usr/local/jamfconnect/SLU.icns'
readonly genericIconFile='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
activeIcon="$SLUIconFile"

# Bundle IDs we care about for mdfind discovery
readonly acrobatBundleIDs=('com.adobe.Acrobat.Pro' 'com.adobe.Acrobat' 'com.adobe.Acrobat.reader')
readonly readerBundleIDs=('com.adobe.Reader' 'com.adobe.AdobeReader')
readonly ccBundleIDs=('com.adobe.acc.AdobeCreativeCloud' 'com.adobe.CCXProcess' 'com.adobe.accmac')

# Fallback paths if Spotlight comes up empty
readonly acrobatPathGlobs=('/Applications/Adobe Acrobat'*)
readonly readerPathGlobs=('/Applications/Adobe Reader'*)
readonly ccPathGlobs=('/Applications/Adobe Creative Cloud'* '/Applications/Utilities/Adobe Creative Cloud'*)

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

# Find installed app paths for a set of bundle IDs, with path-glob fallback
function find_AppPaths() {
    local -n bundleIDs=$1
    local -n fallbackGlobs=$2
    local -a foundPaths=()
    local bundleID path

    # Spotlight by bundle ID
    for bundleID in "${bundleIDs[@]}";
    do
        while IFS= read -r path;
        do
            [[ -n "$path" && -e "$path" ]] && foundPaths+=("$path")
        done < <(/usr/bin/mdfind "kMDItemCFBundleIdentifier == '$bundleID'" 2>/dev/null)
    done

    # Direct path globs 
    if [[ ${#foundPaths[@]} -eq 0 ]];
    then
        for path in "${fallbackGlobs[@]}";
        do
            [[ -e "$path" ]] && foundPaths+=("$path")
        done
    fi

    printf '%s\n' "${foundPaths[@]}"
}

# Remove shared Adobe support files (Acrobat and Reader both drop these)
function remove_SharedAdobeSupport() {
    rm -rf "/Library/Application Support/Adobe/Acrobat"*
    rm -rf "/Library/Internet Plug-Ins/Adobe"*
    rm -rf "/Applications/Utilities/Adobe Sync"
    rm -rf "/Applications/Utilities/Adobe Application"
    rm -rf "/Applications/Utilities/Adobe Installers"
    rm -rf "/Applications/Utilities/Adobe Application Manager"
    rm -rf "/Applications/Utilities/Adobe Genuine Service"
}

# Uninstall Adobe Acrobat
function uninstall_Acrobat() {
    local path
    while IFS= read -r path;
    do
        [[ -n "$path" ]] || continue
        log_Message "Removing: $path"
        rm -rf "$path"
    done < <(find_AppPaths acrobatBundleIDs acrobatPathGlobs)
    remove_SharedAdobeSupport
    log_Message "Uninstalled Adobe Acrobat"
}

# Uninstall Adobe Reader
function uninstall_Reader() {
    local path
    while IFS= read -r path;
    do
        [[ -n "$path" ]] || continue
        log_Message "Removing: $path"
        rm -rf "$path"
    done < <(find_AppPaths readerBundleIDs readerPathGlobs)
    rm -rf "/Library/Application Support/Adobe/Adobe Reader"*
    remove_SharedAdobeSupport
    log_Message "Uninstalled Adobe Reader"
}

# Uninstall Creative Cloud
function uninstall_CC() {
    local path
    while IFS= read -r path;
    do
        [[ -n "$path" ]] || continue
        log_Message "Removing: $path"
        rm -rf "$path"
    done < <(find_AppPaths ccBundleIDs ccPathGlobs)
    rm -rf "/Library/Application Support/Adobe/Creative Cloud"*
    rm -rf "/Applications/Utilities/Adobe Creative Cloud Experience"
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
    local promptText="You are about to receive the latest version of Adobe Acrobat DC Pro.\n\nAll Adobe applications will be closed. Adobe Acrobat, Reader, and Creative Cloud will be uninstalled.\n\nSelect \"Continue\" to begin.\n\n\n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000."
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
