#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 4-15-25   ###
### Updated: 4-15-25   ###
### Version: 1.0       ###
##########################

readonly logPath='/var/log/locationServices_Enable.log'
readonly uuid="$(/usr/sbin/system_profiler SPHardwareDataType | awk '/Hardware UUID:/ { print $3 }')"
readonly locationdPath="/var/db/locationd/Library/Preferences/ByHost/com.apple.locationd.${uuid}"
readonly byHostPath='/var/db/locationd/Library/Preferences/ByHost/com.apple.locationd'
readonly timedPath='/private/var/db/timed/Library/Preferences/com.apple.timed.plist'
readonly genericTimeZoneplist='/Library/Preferences/com.apple.timezone.auto.plist'
readonly dateTimePrefs='/var/db/timed/Library/Preferences/com.apple.preferences.datetime.plist'

# Append current status to log file
function log_Message() {
    printf "Log: $(date "+%F %T") %s\n" "$1" | tee -a "$logPath"
}

function main() {
    printf "Log: $(date "+%F %T") Beginning Location Services Enable script.\n" | tee "$logPath"
    if sudo -u "_locationd" /usr/bin/defaults -currentHost write "$locationdPath" LocationServicesEnabled -int 1;
    then
        log_Message "Set Location Services to enabled."
    else
        log_Message "Unable to set Location Services to enabled."
    fi
    if sudo -u "_locationd" /usr/bin/defaults -currentHost write "$byHostPath" LocationServicesEnabled -int 1;
    then
        log_Message "Set Location Services to enabled for generic file."
    else
        log_Message "Unable to set Location Services to enabled for generic file."
    fi
    /usr/sbin/chown "_locationd:_locationd" "/var/db/locationd/"
    killall -HUP "$(pgrep locationd)"

    if /usr/bin/defaults write "$genericTimeZoneplist" Active -bool YES;
    then
        log_Message "Set Time Zone to Auto."
    else
        log_Message "Unable to set Time Zone to Auto."
    fi

    if sudo -u "_timed" /usr/bin/defaults -currentHost write "$timedPath" TMAutomaticTimeOnlyEnabled -int 1;
    then
        log_Message "Set TMAutomaticTimeOnlyEnabled to true."
    else
        log_Message "Unable to set TMAutomaticTimeOnlyEnabled to true."
    fi

    if sudo -u "_timed" /usr/bin/defaults -currentHost write "$timedPath" TMAutomaticTimeZoneEnabled -int 1;
    then
        log_Message "Set TMAutomaticTimeZoneEnabled to true."
    else
        log_Message "Unable to set TMAutomaticTimeZoneEnabled to true."
    fi

    /usr/sbin/systemsetup -setusingnetworktime on &>/dev/null
    /usr/sbin/systemsetup -gettimezone &>/dev/null
    /usr/sbin/systemsetup -getnetworktimeserver &>/dev/null

    if sudo -u "_timed" /usr/bin/defaults write "$dateTimePrefs" timezoneset -int 1;
    then
        log_Message "Set Date & Time Time Zone to true."
    else
        log_Message "Unable to set Date & Time Time Zone to true."
    fi
}

main
