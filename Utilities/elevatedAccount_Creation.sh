#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 08-27-24  ###
### Updated: 02-09-26  ###
### Version: 3.1       ###
##########################

managementAccount="$4"
managementAccountPass="$5"
elevatedAccount="$6"
elevatedAccountPass=''
readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly currentUserHomePath="${HOME:-/Users/${currentUser}}"
readonly logFile='/var/log/elevatedAccount_Creation.log'
readonly outputFile="${currentUserHomePath}/Desktop/HowTo_AdminAccount.txt"
readonly SLUIconFile='/usr/local/jamfconnect/SLU.icns'
readonly genericIconFile='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
readonly dialogTitle='SLU ITS: Elevated Account Creation'
readonly maxAttempts=10
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

# Ensure external arguments are passed
function check_Args() {
    if [[ -z "$managementAccount" ]] || [[ -z "$managementAccountPass" ]] || [[ -z "$elevatedAccount" ]]; 
    then
        log_Message "Missing critical arguments" "ERROR"
        return 1
    fi
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

# Check if someone is logged into the device
function check_Login() {
	if [[ "$currentUser" == 'loginwindow' ]] || [[ -z "$currentUser" ]] || [[ "$currentUser" == 'root' ]];
	then
		log_Message "No one currently logged in"
		return 1
	else
		log_Message "${currentUser} currently logged in"
		return 0
	fi
}

# Check if account exists
function check_Account() {
	local account="$1"
	/usr/bin/id "$account" >/dev/null
	return $?
}

# Check if account is in the admin group
function check_Admin(){
    local account="$1"
    /usr/sbin/dseditgroup -o checkmember -m "$account" admin &>/dev/null
    return $?
}

# Check account for Secure Token
function check_SecureToken() {
    local account="$1"
    /usr/sbin/sysadminctl -secureTokenStatus "$account" 2>&1 | grep -q 'ENABLED'
    return $?
}

# Creates account with a home folder and proper permissions
function create_AdminAccount() {
    local accountAdd="$1"
    local accountAddPass="$2"
    local accountAddPath="$3"
    local adminAccount="$4"
    local adminPass="$5"
    if /usr/sbin/sysadminctl -addUser "$accountAdd" -password "$accountAddPass" -home "$accountAddPath" -admin -adminUser "$adminAccount" -adminPassword "$adminPass" &>/dev/null;
    then
        log_Message "Successfully created account: \"${accountAdd}\""
        if check_Account "$accountAdd";
        then
            dirs=("Applications" "Desktop" "Documents" "Downloads" "Movies" "Music" "Pictures" "Public")
            for dir in "${dirs[@]}";
            do
                mkdir -p "$accountAddPath/$dir"
                chown "$accountAdd":staff "$accountAddPath/$dir"
                chmod 750 "$accountAddPath/$dir"
            done
            chown -R "$accountAdd":staff "$accountAddPath"
            chmod +a "group:everyone deny delete" "$accountAddPath"
            chmod 750 "$accountAddPath"
            log_Message "Successfully configured: \"${accountAdd}\""
            return 0
        else
            log_Message "Failed to configure: \"${accountAdd}\"" "ERROR"
        fi
    else
        log_Message "Failed to create: \"${accountAdd}\"" "ERROR"
    fi
    return 1
}

# Assigns Secure Token to an account
function token_Action() {
    local tokenAccount="$1"
    local tokenPassword="$2"
    local adminAccount="$3"
    local adminPassword="$4"
    local tokenAction="$5"
    local result
    if [[ "$tokenAction" == 'Add Token' ]];
    then
        result=$(su "$adminAccount" -c "/usr/sbin/sysadminctl -secureTokenOn \"$tokenAccount\" -password \"$tokenPassword\" -adminUser \"$adminAccount\" -adminPassword \"$adminPassword\"" 2>&1)
    elif [[ "$tokenAction" == 'Remove Token' ]];
    then
        result=$(su "$adminAccount" -c "/usr/sbin/sysadminctl -secureTokenOff \"$tokenAccount\" -password \"$tokenPassword\" -adminUser \"$adminAccount\" -adminPassword \"$adminPassword\"" 2>&1)
    else
        log_Message "Invalid token action" "ERROR"
        return 1
    fi
    if check_SecureToken "$tokenEnableAccount";
    then
        return 0
    else
        log_Message "Assign token failed, sysadminctl output: ${result}" "ERROR"
        return 1
    fi
}

# Ensure password complexity
function validate_Password() {
    local password="$1"
    local minLength=10
    if [[ ${#password} -lt $minLength ]];
    then
        alert_Dialog "Weak Password" "Password must be at least $minLength characters"
        return 1
    fi
    if ! [[ "$password" =~ [0-9] ]] || ! [[ "$password" =~ [A-Z] ]] || ! [[ "$password" =~ [a-z] ]];
    then
        alert_Dialog "Weak Password" "Password must contain uppercase, lowercase, and numbers"
        return 1
    fi
    return 0
}

function write_InfoFile() {
    log_Message "Creating output file at: $outputFile"
    if touch "$outputFile";
    then
        cat > "$outputFile" << OOP
  SLU ITS: Local Admin Account 

  Account Username:  elevate
  Account Password:  The password you created during your remote session
  
  When to use it:    ONLY when an admin prompt appears
                     (installing or updating software, changing system settings)

  When NOT to use it: Do NOT use this account to log into your Mac.
                      Continue signing in with your SLU Net ID as usual.


Frequently Asked Questions

Q: How do I log into my Mac?
A: Nothing has changed with how you log in. Continue to sign in with
   your SLU Net ID and password as you always have.

Q: When do I use the elevate account?
A: When you try to install or update an application, or make a change
   to your system settings, macOS may display a prompt asking for an
   administrator username and password. This is when you use the
   elevate account. Enter "elevate" as the username and the password
   you created during our remote session.

Q: What does the admin prompt look like?
A: It is a small window that appears asking for an administrator name
   and password. It typically shows up when installing new software,
   running updates, or modifying system preferences that require
   elevated permissions.

Q: I forgot my elevate account password. What do I do?
A: Two options:
            1. Copy and paste the following command into the Terminal:
                sudo jamf policy -event ElevatedAccountCreation
            2. Reach out to SLU IT at ask.slu.edu

Q: Can I change the elevate account password?
A: Yes. Open System Settings, go to Users & Groups, select the
   elevate account, and choose Change Password. You will need your
   current elevate password to make this change.

  Account created on: $(date "+%F %T")
  This file was placed on your Desktop for your reference.
  Feel free to keep it or delete it once you are comfortable
  with the information above.
OOP
    chown "$currentUser":staff "$outputFile"
    else
        log_Message "Unable to create information file on Desktop"
        return 1
    fi
    return 0
}

# AppleScript - Informing the user and giving them two choices
function binary_Dialog() {
    local promptString="$1"
    local mainButton="$2"
    local secondButton="$3"
    local count=1
    while [ $count -le $maxAttempts ];
    do
        binDialog=$(/usr/bin/osascript <<OOP
        try
            set promptString to "$promptString"
            set mainButton to "$mainButton"
            set secondButton to "$secondButton"
            set iconPath to "$activeIcon"
            set dialogTitle to "$dialogTitle"
            if secondButton is equal to "" then
                set dialogResult to display dialog promptString buttons {mainButton} default button mainButton with icon POSIX file iconPath with title dialogTitle giving up after 900
            else
                set dialogResult to display dialog promptString buttons {secondButton, mainButton} default button mainButton with icon POSIX file iconPath with title dialogTitle giving up after 900
            end if
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
            'CANCEL' | 'Cancel' | "$secondButton")
                log_Message "User responded with: \"$binDialog\""
                return 1
                ;;
            'TIMEOUT' | '')
                log_Message "No response, re-prompting ($count/10)"
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

# AppleScript - Text field dialog prompt for inputting information
function textField_Dialog() {
    local promptString="$1"
    local dialogType="$2"
    local count=1
    while [ $count -le $maxAttempts ];
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
                log_Message "User responded with: \"${textFieldDialog}\""
                return 1
                ;;
            'timeout')
                log_Message "No response, re-prompting ($count/10)" "WARN"
                ((count++))
                ;;
            '')
                log_Message "Nothing entered in text field"
                alert_Dialog "An Error Has Occurred" "Please enter something or select cancel"
                ;;
            *)
                if [[ "$dialogType" == 'hidden' ]];
                then
                    log_Message "Continued through prompt"
                else
                    log_Message "User responded with: \"${textFieldDialog}\""
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
            log_Message "Unable to show alert dialog"
            ;;
        'TIMEOUT')
            log_Message "Alert timed out" "WARN"
            ;;
        *)
            log_Message "Continued through alert dialog"
            ;;
    esac
}

function clean_Env() {
    elevatedAccountPass=''
    elevatedAccountPassVerify=''
    unset elevatedAccountPass
    unset elevatedAccountPassVerify
}

function clean_Exit() {
    clean_Env
    managementAccountPass=''
    unset managementAccountPass
}

function main() {
    trap "clean_Exit" EXIT INT TERM HUP
    printf "Log: $(date "+%F %T") Beginning Elevated Account Creation script\n" | tee "$logFile"

    if ! check_Args;
    then
        log_Message "Exiting at argument check"
        exit 1
    fi

    log_Message "Checking for icon file"
    if ! check_Icon;
    then
        log_Message "Exiting at icon check"
        exit 1
    fi

    log_Message "Checking for currently logged in user"
    if ! check_Login;
    then
        log_Message "Exiting at login check"
        exit 1
    fi

    log_Message "Checking for: \"$managementAccount\""
    if ! check_Account "$managementAccount";
    then
        log_Message "Management account does not exist, exiting" "ERROR"
        alert_Dialog "Missing Account" "${managementAccount} account does not exist!"
        exit 1
    fi

    log_Message "Checking for: \"$elevatedAccount\""
    if check_Account "$elevatedAccount";
    then
        log_Message "Elevate account already exists" "WARN"
        if ! binary_Dialog "'elevate' account already exists!\n\nWould you like to delete this account and create a new one?" "Yes" "No";
        then
            log_Message "Exiting at binary dialog"
            exit 0
        else
            log_Message "Deleting elevate account"
            if sysadminctl -deleteUser "$elevatedAccount" -secure &>/dev/null;
            then
                log_Message "Elevate account deleted"
            else
                log_Message "Unable to delete elevate account" "ERROR"
                exit 1
            fi
        fi
    fi

    log_Message "Checking permissions for: \"$managementAccount\""
    if ! check_Admin "$managementAccount";
    then
        log_Message "Management account is not an admin, exiting" "ERROR"
        alert_Dialog "Insufficient Permissions" "${managementAccount} account is not an admin!"
        exit 1
    fi

    validPass=false
    while [[ "$validPass" == false ]];
    do
        log_Message "Prompting user for elevated account INFO"
        requirements="\n\nYour password must include:\n• At least 10 characters\n• An uppercase letter\n• A number"
        if ! textField_Dialog "Please enter the password you would like to use for your admin account:${requirements}" "hidden";
        then
            log_Message "Exiting at INFO prompt"
            exit 0
        else
            elevatedAccountPass="${textFieldDialog}"
            textFieldDialog=''
            unset textFieldDialog
            if validate_Password "$elevatedAccountPass";
            then
                log_Message "INFO sufficiently complex"
                log_Message "Prompting user to verify INFO"
                if ! textField_Dialog "Verify the password by entering it again:" "hidden";
                then
                    log_Message "Exiting at INFO verification"
                    exit 0
                else
                    elevatedAccountPassVerify="${textFieldDialog}"
                    textFieldDialog=''
                    unset textFieldDialog
                fi

                if [[ "$elevatedAccountPass" == "$elevatedAccountPassVerify" ]];
                then
                    log_Message "INFO match, continuing"
                    elevatedAccountPassVerify=''
                    unset elevatedAccountPassVerify
                    validPass=true
                else
                    log_Message "INFO do not match" "ERROR"
                    alert_Dialog "Password Error" "Passwords do not match!"
                fi
            fi
        fi
    done

    log_Message "Creating account: \"${elevatedAccount}\""
    elevatedAccountPath="/Users/${elevatedAccount}"
    if ! create_AdminAccount "$elevatedAccount" "$elevatedAccountPass" "$elevatedAccountPath" "$managementAccount" "$managementAccountPass";
    then
        log_Message "Exiting at account creation"
        alert_Dialog "Account Creation Error" "Unable to complete account creation!"
        exit 1
    fi

    if ! check_SecureToken "$elevatedAccount";
    then
        log_Message "Secure Token not assigned to: \"${elevatedAccount}\"" "WARN"
        if check_SecureToken "$managementAccount";
        then
            log_Message "Secure Token present for: \"${managementAccount}\""
            if ! token_Action "$elevatedAccount" "$elevatedAccountPass" "$managementAccount" "$managementAccountPass" "Add Token";
            then
                log_Message "Unable to assign Secure Token to: \"${elevatedAccount}\"" "ERROR"
            else
                log_Message "Secure Token successfully assigned to: \"${elevatedAccount}\""
            fi
        else
            log_Message "\"${managementAccount}\" does not have a Secure Token to assign to \"${elevatedAccount}\"" "ERROR"
        fi
    else
        log_Message "Secure Token already assigned to: \"${elevatedAccount}\""
    fi
    clean_Env
    
    write_InfoFile
    outputFileWritten=$?
    binary_Dialog "Process completed successfully!" "OK"
    if [[ $outputFileWritten -eq 0 ]];
    then
        if binary_Dialog "Would you like to open the HowTo_AdminAccount document created on your Desktop for further information on your Admin Account?" "Yes" "No";
        then
            log_Message "Opening output file"
            open "$outputFile"
        else
            log_Message "Skipping opening of output file"
        fi
    else
        log_Message "Unable to write to output file" "WARN"
    fi

    log_Message "Elevated Account Creation finished!" "EXIT"
    exit 0
}

main

