# Fix MDM Enrollment

Re-enroll macOS devices that have lost their connection to Jamf Pro using SSH.

## Description

When a Mac falls out of MDM, Apple requires a human sitting at that Mac to approve the new enrollment and there is no way to push it silently. The end user has to click **Enroll** on a Device Enrollment prompt, and they must be a local administrator to authenticate.

These scripts automate everything around that unavoidable click. Reaching the machine, warning the user, temporarily granting the rights they need, triggering the prompt, and cleaning up afterward.

## Scripts

`fix_MDMEnrollment.sh` - Runs locally and reads the CSV, reaches each host, pushes and then runs the remote script

`setup.expect` - Runs locally and installs the SSH public key on a host using password authentication

`remote_Fix_MDMEnrollment.sh` - Runs remotely and does the actual enrollment work in front of the logged in user

## Usage
1. Gather list of effected devices in a CSV with the headers "Computer Name" and "IP" (Template provided)
2. Download all three scripts into the same folder
3. Create an SSH key for this process and do NOT set a passphrase<br />
   `ssh-keygen -t ed25519 -C "mdmrenewal key" -f ~/.ssh/mdmrenew`
4. Run the following command to start the process
```
bash fix_MDMEnrollment.sh "accountName" "accountPass" "csvFile" "sshKey"

  accountName   Local admin account present on the target devices
  accountPass   Password for that account
  csvFile       Path to the CSV of device names and IPs
  sshKey        Path to the private SSH key
```

Example:

```
bash fix_MDMEnrollment.sh 'admin' 'password' './list_of_devices.csv' "/full/pathto/.ssh/key"
```

## How It Works
`fix_MDMEnrollment.sh` does all of the work, you just have to setup your environment with an SSH key and a list of devices before attempting to run this process.
1. `fix_MDMEnrollment.sh` reads the CSV it is given and tries each machine by hostname, falling back to its IP address.
2. `fix_MDMEnrollment.sh` then calls `setup.expect` and it pushes the local public key into the target's `~/.ssh/authorized_keys`, so the rest of the run uses key authentication instead of a password.
3. `fix_MDMEnrollment.sh` then pushes the `remote_Fix_MDMEnrollment.sh` over that SSH connection, written to `/tmp` on the target, and launched detached with `nohup` and SSH returns immediately so the loop keeps moving through the sheet.
4. On the target device running with sudo, `remote_Fix_MDMEnrollment.sh`:
   - confirms someone is logged into the GUI
   - exits early if the device already reports an MDM enrollment
   - shows an AppleScript dialog in the user's session explaining that an enrollment prompt is coming and that they must select **Enroll**
   - starts a monitor that kills any `sudo` the user attempts to abuse
   - adds the user to the `admin` group
   - runs `profiles renew -type enrollment` inside the user's GUI session so the prompt actually appears on their screen
   - polls until the device reports enrollment, the user closes the enrollment window (**Not Now**), or the timeout expires
   - removes the admin rights, kills the monitor, and reports the result in a final dialog

Admin rights are removed on every exit path, including errors, timeouts, and interrupts.

