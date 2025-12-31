#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 12-30-25  ###
### Updated: 12-31-25  ###
### Version: 1.1       ###
##########################

readonly allArgs="$@"
readonly exportedAppLocation="$1"
readonly appIdentifier="$2"
readonly pkgVersion="$3"
readonly appInstallLocation="$4"
readonly developerID="$5"
readonly pkgName="${6}"
readonly pkgOutputPath="$7"
readonly fullPKGOutputPath="${7}/${6}.pkg"
readonly signedPKGName="${pkgName}-SIGNED"
readonly fullSignedPKGOutputPath="${7}/${signedPKGName}.pkg"
readonly notaryPassName='notarytool-password'
readonly logFile="${HOME}/Desktop/create_PKGfromApp.log"

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

# Show argument examples
function show_Help() {
    printf "\n"
    log_Message "Requirements:"
    log_Message "1. Exported App Location"
    log_Message "    - /Applications/AppName.app"
    log_Message "2. App Identifier"
    log_Message "    - com.DevName.AppName"
    log_Message "3. Output Package Version"
    log_Message "    - 1.3"
    log_Message "4. Output Package Install Location"
    log_Message "    - /Applications/AppName.app"
    log_Message "5. Developer ID"
    log_Message "    - Developer ID Installer: Name (Team ID)"
    log_Message "6. Output Package Name (Do not include .pkg)"
    log_Message "    - install_AppName-ver"
    log_Message "7. Output Package Location"
    log_Message "    - /Users/user/Documents"
    printf "\n"
}

# Ensure provided arguments are present and valid
function validate_Args() {
    local missing=0
    log_Message "Verifying program arguments"
    if [[ -z "$exportedAppLocation" ]];
    then
        log_Message "Missing - App Root Location" "WARN"
        ((missing++))
    elif [[ ! -d "$exportedAppLocation" ]];
    then
        log_Message "App Root Location does not exist! Check the provided path" "WARN"
        ((missing++))
    fi

    if [[ -z "$appIdentifier" ]];
    then
        log_Message "Missing - App Identifier" "WARN"
        log_Message "Example: com.DevName.AppName"
        ((missing++))
    fi

    if [[ -z "$appInstallLocation" ]];
    then
        log_Message "Missing - App Install Location" "WARN"
        ((missing++))
    fi

    if [[ -z "$developerID" ]];
    then
        log_Message "Missing - Developer ID" "WARN"
        log_Message "Example: Developer ID Installer: Name (Team ID)"
        ((missing++))
    fi

    if [[ -z "$pkgName" ]];
    then
        log_Message "Missing - Output PKG Name" "WARN"
        ((missing++))
    fi

    if [[ -z "$pkgVersion" ]];
    then
        log_Message "Missing - Output PKG Version" "WARN"
        ((missing++))
    fi

    if [[ -z "$pkgOutputPath" ]];
    then
        log_Message "Missing - Output PKG Path" "WARN"
        ((missing++))
    fi

    if [ $missing -eq 1 ];
    then
        log_Message "Missing critical argument!" "ERROR"
        return 1
    elif [ $missing -gt 0 ];
    then
        log_Message "Missing critical arguments!" "ERROR"
        return 1
    elif [ $missing -eq 0 ];
    then
        log_Message "All arguments verified"
        return 0
    else
        log_Message "Unknown arguments" "ERROR"
        return 1
    fi
}

function main() {
	if [[ -w "$logFile" ]];
	then
		printf "Log: $(date "+%F %T") Beginning Create PKG from App script\n" | tee "$logFile"
	else
		printf "Log: $(date "+%F %T") Beginning Create PKG from App script\n"
	fi

    if [[ "${allArgs[@]}" == '' ]];
    then
        log_Message "No arguments provided"
        show_Help
        exit 1
    fi

    if ! validate_Args;
    then
        show_Help
        log_Message "Exiting at argument validation" "ERROR"
        exit 1
    fi

    log_Message "Beginning pkgbuild"
    if pkgbuild --root "$exportedAppLocation" --identifier "$appIdentifier" --version "$pkgVersion" --install-location "$appInstallLocation" --sign "$developerID" "$fullPKGOutputPath" 1> "$logFile";
    then
        log_Message "pkgbuild complete!"
        log_Message "PKG location: ${fullPKGOutputPath}"
    else
        log_Message "Unable to complete pkgbuild" "ERROR"
        exit 1
    fi

    log_Message "Beginning productsign"
    if productsign --sign "$developerID" "$fullPKGOutputPath" "$fullSignedPKGOutputPath" 1> "$logFile";
    then
        log_Message "productsign complete!"
        log_Message "Signed PKG Location: ${fullSignedPKGOutputPath}"
    else
        log_Message "Unable to complete productsign" "ERROR"
        exit 1
    fi

    log_Message "Beginning xcrun notary"
    if xcrun notarytool submit "$fullSignedPKGOutputPath" --keychain-profile "$notaryPassName" --wait 1> "$logFile";
    then
        log_Message "xcrun notary complete!"
    else
        log_Message "Unable to complete xcrun notary" "ERROR"
        exit 1
    fi

    log_Message "Beginning xcrun staple"
    if xcrun stapler staple "$fullSignedPKGOutputPath" 1> "$logFile";
    then
        log_Message "xcrun staple complete!"
    else
        log_Message "Unable to complete xcrun staple" "ERROR"
    fi

    log_Message "PKG signature:"
    spctl -a -t install -vv "$fullSignedPKGOutputPath" | tee -a "$logFile"
    log_Message "Process complete!"
    exit 0
}

main

