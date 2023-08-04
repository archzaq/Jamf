#!/bin/bash

##########################
### Author: Zac Reeves ###
##########################

# Variables
itsName="$4"
itsPassword="$5"
currentUser="$(defaults read /Library/Preferences/com.apple.loginwindow lastUserName)"
currentDeviceName="$(hostname)"

# Prompt the user for their password, reprompting if they enter nothing or the dialog times out
function password_Prompt(){
	echo "Prompting user for their password"

	# AppleScript to securely prompt the user for their password
	currentUserPassword=$(osascript <<EOF
	    set currentUserPassword to (display dialog "Please enter your computer password to grant its_admin a secure token:" buttons {"OK"} default button "OK" with hidden answer default answer "" with title "SLU ITS: MacOS Secure Token - Password Prompt" giving up after 900)
	    if button returned of currentUserPassword is equal to "OK" then
	        return text returned of currentUserPassword
	    else
	        return "timeout"
	    end if
EOF
	)
	# If no password is entered, reprompt for their password
	if [[ "$currentUserPassword" == '' ]];
	then
	    echo "No password entered"
	    osascript -e "display dialog \"Error! You did not enter a password. Please try again.\" buttons {\"OK\"} default button \"OK\" with title \"SLU ITS: MacOS Secure Token - Password Prompt\""
	    password_Prompt

	# If the dialog box timed out, reprompt for their password
	elif [[ "$currentUserPassword" == 'timeout' ]];
	then
		password_Prompt
	fi
}

# Checks for a secure token, if the current user doesnt have one, exit.
# If its_admin doesnt have one, grant a secure token.
function token_Check(){
	# Check user for a secure token
	if sysadminctl -secureTokenStatus "$1" 2>&1 | grep -q 'ENABLED';
	then
	    echo "User \"$1\" has a secure token"
	    if [[ "$1" == "$itsName" ]]; 
		then
			token=true
		fi
	    
	# If the user has no secure token, assign one
	else

		echo "User \"$1\" does not have a secure token"

		# If the user without a secure token is the currently logged in user, exit
		if [[ "$1" == "$currentUser" ]]; 
		then
			osascript -e "display dialog \"Rerun the policy from an account with a secure token!\" buttons {\"OK\"} default button \"OK\" with title \"SLU ITS: MacOS Secure Token\""
			echo "Since the user \"$currentUser\" does not have a secure token, exiting script.."
			exit 1

		# Assigns its_admin a secure token using the current user's credentials
		elif [[ "$1" == "$itsName" ]];
		then

			# Ensure this script isnt ran while signed in as its_admin
			if [[ "$currentUser" == "$itsName" ]];
		    then
		    	osascript -e "display dialog \"Rerun the policy from an account with a secure token other than its_admin!\" buttons {\"OK\"} default button \"OK\" with title \"SLU ITS: MacOS Secure Token\""
		    	echo "Current user is $currentUser, unable to proceed. Exiting..."
		    	exit 1
		    fi

		    # Function to check currently signed in user for a secure token, exiting if not
    		token_Check "$currentUser"

			osascript -e "display dialog \"Your partners in ITS are working to enhance the security of your Mac. To finish this enhancement, your user password is required. \n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000.\" buttons {\"OK\"} default button \"OK\" with title \"SLU ITS: MacOS Secure Token - Password Prompt\""

			# Function to prompt currently logged in user for their password
			password_Prompt

			# Function to assign its_admin a secure token using the current user's credentials
			assign_Token
		else
			echo "Error! Not sure what happened, exiting..."
			exit 1
		fi
	fi
}

# Assigns its_admin a secure token using the current user's credentials
function assign_Token(){

	# Test the sysadminctl command for a success before actually attempting to grant a secure token
	output=$(sysadminctl -adminUser "$currentUser" -adminPassword "$currentUserPassword" -secureTokenOn "$itsName" -password "$itsPassword" -test 2>&1)

	# If the test was successful, assign its_admin a secure token
	if [[ $output == *"Done"* ]];
	then
	    echo "Success!!"
	    sysadminctl -adminUser "$currentUser" -adminPassword "$currentUserPassword" -secureTokenOn "$itsName" -password "$itsPassword"
	    osascript -e "display dialog \"its_admin was successfully granted a secure token!\" buttons {\"OK\"} default button \"OK\" with title \"SLU ITS: MacOS Secure Token\""

	# If the test was not successful, exit
	else
	    echo "Error with sysadminctl command"
	    osascript -e "display dialog \"Error! its_admin has not been granted a secure token. Please try again.\" buttons {\"OK\"} default button \"OK\" with title \"SLU ITS: MacOS Secure Token\""
	    exit 1
	fi
}

# Check for its_admin to be in the admin group
function admin_Check(){

	# Gather list of groups for the user
	groupList=$(groups "$1")

	# If the user is not an admin, grant admin rights
	if [[ ! $groupList == *"admin"* ]];
	then

		# If user had a secure token but wasnt an Admin, prompt current user for their password as they missed the previous password prompt
		if [[ $token ]];
		then
			password_Prompt
		fi

		# Add user to admin group
		dseditgroup -o edit -a "$1" -u "$currentUser" -P "$currentUserPassword" -t user -L admin # Adds its_admin to admin group

		# Gather list of groups for the user
		groupList2=$(groups "$1")

		# Double checks user to be in the admin group
		if [[ $groupList2 == *"admin"* ]];
		then
			echo "$1 added to Admin group."
		else
			echo "$1 not added to Admin group."
			exit 1
		fi
	else
		echo "$1 is already an Admin"
	fi
}

# Contains all the things
function main(){
    # Check for its_admin account and for it to have a secure token.
    # Creates its_admin if it doesnt exist, and assign secure token if not enabled
    if ls /Users/ | grep -q 'its_admin';
    then

        echo "$itsName exists. Checking for secure token and Admin permissions..."

        # Function to check its_admin for a secure token. If not, check the current user for a secure token and assign one to its_admin if possible, otherwise exit.
        token_Check "$itsName"

        # Function to check for its_admin to be an Admin, assigning the permission if not
        admin_Check "$itsName"
    else

        echo "No $itsName account. Creating $itsName."

        # Function to check currently signed in user for a secure token, exiting if not
    	token_Check "$currentUser"
        
        # Inform the user they will be prompted for their password
        osascript -e "display dialog \"Your partners in ITS are working to enhance the security of your Mac. To finish this enhancement, your user password is required. \n\nIf you have any questions or concerns, please contact the IT Service Desk at (314)-977-4000.\" buttons {\"OK\"} default button \"OK\" with title \"SLU ITS: MacOS Secure Token - Password Prompt\""
        
        # Function to prompt currently logged in user for their password
        password_Prompt

        # Create the its_admin account and assign it to the admin group
        sysadminctl -addUser "$itsName" -password "$itsPassword" -home /Users/its_admin -admin -createHome -adminUser "$currentUser" -adminPassword "$currentUserPassword"
        
        # Function to assign its_admin a secure token using the current user's credentials
        assign_Token
    fi

	# Double check secure token status before attempting CyberArk install
	if sysadminctl -secureTokenStatus "$itsName" 2>&1 | grep -q 'ENABLED';
	then

		# Check for CyberArk to alreade be installed
		if [[ -d "/Applications/CyberArk EPM.app" ]];
		then
			echo "CyberArk already installed. Exiting..."
			exit 0
		fi

		echo "Success! Deploying CyberArk policy to $currentDeviceName"

		# Deploy the CyberArk installation policy and exit
		/usr/local/bin/jamf policy -event CyberArkEPMInstallPolicy &
		exit 0
	else
		echo "Error! its_admin still does not have a secure token. Exiting..."
		exit 1
	fi
}

# Call the main function to start the script
main