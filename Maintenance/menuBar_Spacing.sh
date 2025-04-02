#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 4-2-25    ###
### Updated: 4-2-25    ###
### Version: 1.0       ###
##########################

readonly logPath='/var/log/menuBar_Spacing.log'

# Append current status to log file
function log_Message() {
    printf "Log: $(date "+%F %T") %s\n" "$1" | tee -a "$logPath"
}

function main() {
    printf "Log: $(date "+%F %T") Beginning Menu Bar Spacing script.\n" | tee "$logPath"
    if /usr/bin/defaults -currentHost write -globalDomain NSStatusItemSpacing -int 10;
    then
        log_Message "Successfully set Menu Bar icon spacing."
        if /usr/bin/defaults -currentHost write -globalDomain NSStatusItemSelectionPadding -int 8;
        then
            log_Message "Successfully set Menu Bar icon selection spacing."
        else
            log_Message "Unable to set Menu Bar icon selection spacing."
        fi
    else
        log_Message "Unable to set Menu Bar icon spacing."
        log_Message "Exiting without making any changes."
        exit 1
    fi
    log_Message "Exiting!"
    exit 0
}

main

