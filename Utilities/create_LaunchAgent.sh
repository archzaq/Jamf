#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 09-02-25  ###
### Updated: 11-13-25  ###
### Version: 1.1       ###
##########################

readonly logFile='/var/log/create_LaunchAgent.log'

# Check if Jamf binary exists to determine which parameters to use
if [[ -f "/usr/local/jamf/bin/jamf" ]];
then
    readonly agentLabel="$4"
    readonly programArgument1="$5"
    readonly programArgument2="$6"
else
    readonly agentLabel="$1"
    readonly programArgument1="$2"
    readonly programArgument2="$3"
fi

if [[ -z "$agentLabel" ]] || [[ -z "$programArgument1" ]] || [[ -z "$programArgument2" ]]; 
then
    printf "Missing critical arguments\n"
    exit 1
else
    readonly agentName="${agentLabel}.plist"
    readonly agentPath="/Library/LaunchAgents/${agentName}"
fi

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

# Check if someone is logged into the device
function login_Check() {
    currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
    if [[ "$currentUser" == 'loginwindow' ]] || [[ -z "$currentUser" ]] || [[ "$currentUser" == 'root' ]];
    then
        log_Message "No one currently logged in"
        return 1
    else
        log_Message "${currentUser} currently logged in"
        return 0
    fi
}

function main() {
    if [[ -w "$logFile" ]];
    then
        printf "Log: $(date "+%F %T") Beginning Create LaunchAgent script\n" | tee "$logFile"
    else
        printf "Log: $(date "+%F %T") Beginning Create LaunchAgent script\n"
    fi

    if /usr/bin/defaults write "$agentPath" Label "$agentLabel";
    then
        log_Message "Successfully set LaunchAgent Label"
    else
        log_Message "Unable to set LaunchAgent Label" "ERROR"
        exit 1
    fi

    if /usr/bin/defaults write "$agentPath" ProgramArguments -array "$programArgument1" "$programArgument2";
    then
        log_Message "Successfully set LaunchAgent ProgramArguments"
    else
        log_Message "Unable to set LaunchAgent ProgramArguments" "ERROR"
        exit 1
    fi

    if /usr/bin/defaults write "$agentPath" RunAtLoad -boolean true;
    then
        log_Message "Successfully set LaunchAgent RunAtLoad"
    else
        log_Message "Unable to set LaunchAgent RunAtLoad" "ERROR"
        exit 1
    fi

    if /usr/bin/plutil -convert xml1 "$agentPath" &>/dev/null;
    then
        log_Message "LaunchAgent plist set to XML"
    else
        log_Message "Unable to set LaunchAgent plist to XML" "ERROR"
        exit 1
    fi

    if /usr/bin/plutil -lint "$agentPath" &>/dev/null;
    then
        log_Message "LaunchAgent successfully verified"
    else
        log_Message "Unable to verify LaunchAgent" "ERROR"
        exit 1
    fi

    if chown root:wheel "$agentPath";
    then
        log_Message "LaunchAgent ownership set to root:wheel"
    else
        log_Message "Unable to set LaunchAgent ownership" "ERROR"
        exit 1
    fi

    if chmod 644 "$agentPath";
    then
        log_Message "LaunchAgent set to readonly"
    else
        log_Message "Unable to set LaunchAgent to readonly" "ERROR"
        exit 1
    fi

    if login_Check;
    then
        readonly uid=$(id -u "$currentUser")
        if /bin/launchctl bootstrap gui/"$uid" "$agentPath";
        then
            log_Message "LaunchAgent loaded for ${currentUser}"
        else
            log_Message "Unable to load LaunchAgent for ${currentUser}" "WARN"
        fi
    fi

    exit 0
}

main
