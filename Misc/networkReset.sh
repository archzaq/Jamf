#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 3-3-25    ###
### Updated: 3-6-25    ###
### Version: 1.0       ###
##########################

readonly userAccount="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly userHomeFolder="/Users/${userAccount}"
readonly backupFolderLocation="${userHomeFolder}/.SLU"
readonly backupTempFolder="${backupFolderLocation}/networkFiles"
readonly backupTarLocation="${backupFolderLocation}/networkFiles.tgz"
readonly systemConfigurationFolder='/Library/Preferences/SystemConfiguration'
readonly iconPath='/usr/local/jamfconnect/SLU.icns'
readonly dialogTitle='SLU ITS: Network Reset'
readonly logPath='/var/log/networkReset.log'
readonly networkFilesArray=( 
    "com.apple.airport.preferences.plist"
    "com.apple.network.identification.plist"
    "com.apple.network.eapolclient"
    "com.apple.network.configuration.plist"
    "preferences.plist"
    "com.apple.wifi.message-tracer.plist"
    "NetworkInterfaces.plist"
)

# Check for SLU icon file, AppleScript dialog boxes will error without it
function icon_Check() {
    if [[ ! -f "$iconPath" ]];
    then
        log_Message "No SLU icon found, attempting install."
        /usr/local/bin/jamf policy -event SLUFonts
        if [[ ! -f "$iconPath" ]];
        then
            log_Message "No SLU icon found, exiting."
            return 1
        fi
    fi
    log_Message "SLU icon found."
    return 0
}

# Check if someone is logged into the device
function login_Check() {
    if [[ "$userAccount" == 'root' ]];
    then
        log_Message "\"root\" currently logged in."
        return 1
    elif [[ "$userAccount" == 'loginwindow' ]] || [[ -z "$userAccount" ]];
    then
        log_Message "No one logged in."
        return 1
    else
        log_Message "\"$userAccount\" currently logged in."
        return 0
    fi
}
# AppleScript - Informing the user and giving them two choices
function binary_Dialog() {
    local promptString="$1"
    local count=1
    while [ $count -le 10 ];
    do
        binDialog=$(/usr/bin/osascript <<OOP
        try
            set promptString to "$promptString"
            set iconPath to "$iconPath"
            set dialogTitle to "$dialogTitle"
            set dialogResult to display dialog promptString buttons {"Cancel", "Continue"} default button "Continue" with icon POSIX file iconPath with title dialogTitle giving up after 900
            set buttonChoice to button returned of dialogResult
            if buttonChoice is equal to "Continue" then
                return buttonChoice
            else
                return "timeout"
            end if
        on error
            return "cancelled"
        end try
OOP
        )
        case "$binDialog" in
            'cancelled')
                log_Message "User selected cancel."
                return 1
                ;;
            'timeout')
                log_Message "No response, re-prompting ($count/10)."
                ((count++))
                ;;
            *)
                log_Message "User responded with: $binDialog"
                return 0
                ;;
        esac
    done
    return 1
}

# Look for specific networking files, if present, backup and then delete them
function backup_Network_Files() {
    for backupNetworkFile in "${networkFilesArray[@]}";
    do
        local fullFilePath="${systemConfigurationFolder}/${backupNetworkFile}"
        if [[ -f "$fullFilePath" ]];
        then
            log_Message "Backing up $fullFilePath"
            cp "$fullFilePath" "$backupTempFolder"
            if [[ $? -eq 0 ]];
            then
                log_Message "Removing $fullFilePath"
                /bin/rm "$fullFilePath"
            else
                log_Message "Failed to copy $fullFilePath"
            fi
        fi
    done
    cd "${backupFolderLocation}" && su "$userAccount" -c "/usr/bin/tar -czf \"${backupTarLocation}\" networkFiles"
    if [[ $? -eq 0 ]];
    then
        log_Message "Backed up network files are located at $backupTarLocation"
        /bin/rm -r "$backupTempFolder"
    else
        log_Message "tar command failed."
    fi
}

# AppleScript - Informing the user of what took place
function inform_Dialog() {
    local promptString="$1"
    local count=1
    while [ $count -le 10 ];
    do
        informDialog=$(/usr/bin/osascript <<OOP
        set promptString to "$promptString"
        set iconPath to "$iconPath"
        set dialogTitle to "$dialogTitle"
        set dialogResult to display dialog promptString buttons {"OK"} default button "OK" with icon POSIX file iconPath with title dialogTitle giving up after 900
        set buttonChoice to button returned of dialogResult
        if buttonChoice is equal to "OK" then
            return buttonChoice
        else
            return "timeout"
        end if
OOP
        )
        case "$informDialog" in
            'timeout')
                log_Message "No response, re-prompting ($count/10)."
                ((count++))
                ;;
            *)
                log_Message "User responded with: $informDialog"
                return 0
                ;;
        esac
    done
    return 1
}

# Append current status to log file
function log_Message() {
    echo "Log: $(date "+%F %T") $1" | tee -a "$logPath"
}

function main() {
    echo "Log: $(date "+%F %T") Beginning Network Reset script." | tee "$logPath"

    if ! icon_Check;
    then
        log_Message "Exiting for no SLU icon."
        exit 1
    fi
    
    if ! login_Check;
    then
        log_Message "Exiting for invalid user logged in."
        exit 1
    fi

    log_Message "Displaying first dialog."
    if ! binary_Dialog "Welcome to the Network Reset Tool!\n\nIf you choose to continue, you will be deleting all saved preferences and settings relating to internet and wireless functionality.";
    then
        log_Message "Exiting at first dialog."
        exit 0
    fi

    if [[ ! -d "$backupTempFolder" ]];
    then
        log_Message "Creating backup folder at $backupFolderLocation"
        su $userAccount -c "mkdir -p $backupTempFolder"
    else
        log_Message "Backup folder already exists."
    fi

    backup_Network_Files

    log_Message "Displaying last dialog."
    if ! inform_Dialog "Process Completed!\n\nPlease restart the computer to reconfigure your internet and wireless functionality.";
    then
        log_Message "Exiting at last dialog."
        exit 0
    fi
    log_Message "Exiting!"
    exit 0
}

main
