JamfConnect_ExistingDeployment.sh:
    With this script, you can deploy Jamf Connect to devices that are already setup in the environment.
    The script is part of a policy that contains two pkgs. The policy installs the Jamf Connect Launch Agent and our custom branding. Once those packages are installed, the script runs, triggering the jamf recon command. When the inventory update completes, the script then waits for all the appropriate Jamf Connect pieces to be in place before prompting the user to restart and authenticate with Okta using Jamf Connect.

JamfConnect_ForcedExistingDeployment.sh:
    Will act the same as the existing deployment script but has more error checking and added a way for the user to delay the install of Jamf Connect.

JamfConnect_Removal.sh:
    Removes Jamf Connect from a device.

JamfConnect_UserPrompt.sh
    Annoy folk into initiating the Jamf Connect install.
