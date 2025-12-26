## Table of Contents
1. [[#Main]]
  - [[#General]]
  - [[#Enrollment]]
  - [[#Recon]]
  - [[#Update]]
2. [[#Maintenance]]
  - [[#Rename]]
  - [[#Management Account Fix]]
  - [[#Self Service Fix]]
3. [[#Utilities]]
  - [[#Elevated Account Creation]]
  - [[#Network Reset]]
  - [[#Secure Token Manager]]
4. [[#Jamf Connect]]
  - [[#InstallJamfConnect]]
  - [[#RemoveJamfConnect]]
  - [[#ReinstallJamfConnect]]
  - [[#RepairJamfConnect]]
5. [[#Security]]
  - [[#Cortex 8.8 Install]]
  - [[#CyberArk 25.3 Install]]
6. [[#Self Service]]
  - [[#Adobe Acrobat Pro - Shared Install]]
  - [[#BitLocker Search]]


# Main
---
## General
```bash
sudo jamf policy
```
#### Description
Checks for any pending/missing policies and installs them
**Log Location:** `/var/log/jamf.log`

## Enrollment
```bash
sudo jamf policy -event enrollmentComplete
```
#### Description
Checks for any pending/missed policies set to run after a device's enrollment into Jamf
**Log Location:** `/var/log/jamf.log`

## Recon
```bash
sudo jamf recon
```
#### Description
Gathers information about the device and sends its status to Jamf Pro
**Log Location:** `??`

## Update
```bash
sudo jamf policy -event Update
```
#### Description
Checks for missed [enrollment](#Enrollment) policies, [general](#General) policies, runs [recon](#Recon), ensures Rosetta is installed, ensure the device doesn't have mismatched names, and ensures [[#Jamf Connect]] is installed
**Log Location:** `/var/log/updateInventory.log`
**Self Service:** `Update Inventory`
#### Steps
1. [`Maintenance - Check Policy and Update Inventory - Script`](https://github.com/archzaq/Jamf/blob/main/Maintenance/updateInventory.sh)


# Maintenance
---
## Rename
```bash
sudo jamf policy -event rename
```
#### Description
Prompts the user to choose their department prefix then sets the device name to `Prefix-Serial` using the last six characters of the serial number. If the device name already has a prefix, ask the user if they would like to keep the existing prefix
**Log Location:** `/var/log/computerRenameMenu.log`
#### Steps
1. [`Computer Rename - Department Menu - Script`](https://github.com/archzaq/Jamf/blob/main/Maintenance/ComputerRenameMENU.sh)

## Management Account Fix
```bash
# Sets management account to new password
sudo jamf policy -event managementFixNew

# Sets management account to old password
sudo jamf policy -event managementFixOld
```
#### Description
Using a temporary admin account and the logged in user's secure token, this policy attempts to fix any issues that may exist with the management account. Ensures the username, password, admin permissions, and secure token status of the management account are correct
**Log Location:** `/var/log/management_Fix.log`
#### Steps
1. Create `temp_management` account
2. [`Maintenance - Management Account Fix - Script`](https://github.com/archzaq/Jamf/blob/main/Maintenance/management_Fix.sh)

## Self Service Fix
```bash
sudo jamf policy -event FixSelfService
```
#### Description
Deletes the keychain named after the SPHardwareDataType UUID for each user on the device
#### Steps
1. [`Self Service - Keychain Issues - Script`](https://github.com/archzaq/Jamf/blob/main/Maintenance/selfService_Fix.sh)


# Utilities
---
## Elevated Account Creation
```bash
sudo jamf policy -event ElevatedAccountCreation
```
#### Description
If a device has been approved for an admin account, this policy will be available. Running this policy will create the local admin account and prompt the currently signed in user for the password to use for the account. If the account already exists, the current user will be asked if they want to delete and recreate the local admin account (forgotten password).
**Log Location:** `/var/log/elevatedAccount_Creation.log`
#### Steps
1. [`Elevate Account Creation - Script`](https://github.com/archzaq/Jamf/blob/main/Utilities/elevatedAccount_Creation.sh)

## Network Reset
```bash
sudo jamf policy -event NetworkReset
```
#### Description
Attempts to hard reset all network settings of a device, needs work honestly
**Log Location:** `/var/log/networkReset.log`
#### Steps
1. [`Network Reset - Script`](https://github.com/archzaq/Jamf/blob/main/Utilities/network_Reset.sh)

## Secure Token Manager
```bash
sudo jamf policy -event SecureTokenManager
```
#### Description
Run this policy to check Secure Token status for all users on the device. This policy can also be used to add or remove Secure Tokens
#### Steps
1. Create `temp_management` account
2. [`Secure Token - Token Manager - Script`](https://github.com/archzaq/Jamf/blob/main/Utilities/token_Manager.sh)


# Jamf Connect
---
## InstallJamfConnect
```bash
sudo jamf policy -event InstallJamfConnect
```
#### Description
Installs the necessary packages for Jamf Connect. The script attempts to ensure all Jamf Connect packages and configuration profiles are installed before continuing. May get stuck during the [[#Recon]] part of the script.
**Log Location:** `/var/log/JamfConnect_Deployment.log`
#### Steps
1. Installs three packages
	- Jamf Connect Launch Agent
	- SLU Logos Jamf Connect Signed - Package
	- Jamf Connect 2.44
2. [`Jamf Connect - Deployment - Script`](https://github.com/archzaq/Jamf/blob/main/Applications/Jamf%20Connect/JamfConnect_Deployment.sh)

## RemoveJamfConnect
```bash
sudo jamf policy -event RemoveJamfConnect
```
#### Description
Attempts to remove Jamf Connect application, Managed Preferences, Application Support Receipts, Security Agent Login Bundle, and JamfConnect Application Support folder
**Log Location:** `/var/log/JamfConnect_Removal.log`
#### Steps
1. [`Jamf Connect - Removal - Script`](https://github.com/archzaq/Jamf/blob/main/Applications/Jamf%20Connect/JamfConnect_Removal.sh)

## ReinstallJamfConnect
```bash
sudo jamf policy -event ReinstallJamfConnect
```
#### Description
Checks for Jamf Connect Application, Security Bundle, or PLIST file. If found, runs [[#RemoveJamfConnect]], then [[#InstallJamfConnect]]
**Log Location:** `/var/log/JamfConnect_Reinstall.log`
**Self Service:** `Jamf Connect - Install`
#### Steps
1. [`Jamf Connect - Removal and Reinstall - Script`](https://github.com/archzaq/Jamf/blob/main/Applications/Jamf%20Connect/JamfConnect_Reinstall.sh)

## RepairJamfConnect 
```bash
sudo jamf policy -event RepairJamfConnect
```
#### Description
Installs the necessary packages for Jamf Connect, attempts to set the login screen to use Jamf Connect, then runs [[#Recon]]
**Log Location:** `/var/log/jamf.log`
#### Steps
1. Installs four packages
	- Jamf Connect Launch Agent
	- SLU Acceptable Use Signed - Package
	- SLU Logos Jamf Connect Signed - Package
	- Jamf Connect 2.44
2. `sudo authchanger -reset -JamfConnect`
3. `sudo jamf recon`


# Security
---
## Cortex 8.8 Install
```bash
sudo jamf policy -event Cortex8.8
```
#### Description
Since I am unable to disable anti-tampering, this policy uninstalls Cortex XDR, attempts to install version 8.8, then attempts to check-in with Cortex. If unable to install Cortex 8.8, attempt to install Cortex 8.5
**Log Location:** `/var/log/cortex_Upgrade.log`
#### Steps
1. [`Cortex XDR - Upgrade - Script`](https://github.com/archzaq/Jamf/blob/main/Applications/Cortex/cortex_Upgrade.sh)

## CyberArk 25.3 Install
```bash
sudo jamf policy -event CyberArkUpdate
```
#### Description
Ensures the management account password isn't the old password, then attempts to install the new package
**Log Location:** `/var/log/CyberArk_Update.log`
#### Steps
1. `sudo jamf policy -event CyberArkPWChange`
	- [`CyberArk EPM Agent - Pass Change - Script`](https://github.com/archzaq/Jamf/blob/main/Applications/CyberArk/CyberArk_Update.sh)
2. `sudo jamf policy -event CyberArk25.3`


# Self Service
---
## Adobe Acrobat Pro - Shared Install
```bash
sudo jamf policy -event sharedAdobe
```
#### Description
Installs Adobe Acrobat Pro and Creative Cloud for lab devices. Installing from Self Service also runs `caffeinate -d` so the device doesn't sleep during the long installation
**Self Service:** `Adobe Application Suite`
#### Steps
1. Installs one package
	- macOS (Universal) Adobe Pro - 11-15-24.pkg
2. `sudo jamf recon`

## BitLocker Search
```bash
sudo jamf policy -event BitLockerSearch
```
#### Description
Installs the custom application made for searching through SLU BitLocker files on macOS
**Self Service:** `BitLocker Search`
#### Steps
1. Installs one package
	-  BitLocker Search 1.4(1)

