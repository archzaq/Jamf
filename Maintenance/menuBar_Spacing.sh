#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 4-2-25    ###
### Updated: 4-2-25    ###
### Version: 1.4       ###
##########################

readonly logPath='/var/log/menuBar_Spacing.log'

# Append current status to log file
function log_Message() {
    printf "Log: $(date "+%F %T") %s\n" "$1" | tee -a "$logPath"
}

# Check if someone is logged into the device
function login_Check() {
    account="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
    if [[ "$account" == 'root' ]] || [[ "$account" == 'loginwindow' ]] || [[ -z "$account" ]];
    then
        log_Message "Invalid user logged in: $account"
        return 1
    else
        log_Message "Valid user logged in: $account"
        return 0
    fi
}

function main() {
    printf "Log: $(date "+%F %T") Beginning Menu Bar Spacing script.\n" | tee "$logPath"
    if ! login_Check;
    then
        log_Message "Exiting at login check."
        exit 1
    fi
    log_Message "Setting Menu Bar icon spacing."
    if su "$account" -c "/usr/bin/defaults -currentHost write -globalDomain NSStatusItemSpacing -int 10";
    then
        log_Message "Successfully set Menu Bar icon spacing."
        log_Message "Setting Menu Bar icon selection spacing."
        if su "$account" -c "/usr/bin/defaults -currentHost write -globalDomain NSStatusItemSelectionPadding -int 8";
        then
            log_Message "Successfully set Menu Bar icon selection spacing."
            log_Message "Exiting!"
            exit 0
        else
            log_Message "Unable to set Menu Bar icon selection spacing."
        fi
    else
        log_Message "Unable to set Menu Bar icon spacing."
    fi
    log_Message "Exiting and reverting changes."
    su "$account" -c "/usr/bin/defaults -currentHost delete -globalDomain NSStatusItemSpacing"
    su "$account" -c "/usr/bin/defaults -currentHost delete -globalDomain NSStatusItemSelectionPadding"
    exit 1
}

main

