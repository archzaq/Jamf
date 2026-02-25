## Table of Contents
1. [Main](#main)
   - [General Policy](#general-policy)
   - [Enrollment](#enrollment)
   - [Recon](#recon)
   - [Update](#update)
2. [Maintenance](#maintenance)
   - [Rename](#rename)
   - [Management Account Fix](#management-account-fix)
   - [Self Service Fix](#self-service-fix)
3. [Utilities](#utilities)
   - [Elevated Account Creation](#elevated-account-creation)
   - [Menu Bar Spacing](#menu-bar-spacing)
   - [Network Reset](#network-reset)
   - [Secure Token Manager](#secure-token-manager)
4. [Jamf Connect](#jamf-connect)
   - [InstallJamfConnect](#installjamfconnect)
   - [RemoveJamfConnect](#removejamfconnect)
   - [ReinstallJamfConnect](#reinstalljamfconnect)
   - [RepairJamfConnect](#repairjamfconnect)
5. [Security](#security)
   - [Cortex 8.8 Install](#cortex-88-install)
   - [CyberArk 25.3 Install](#cyberark-253-install)
   - [Rapid7 Install](#rapid7-install)
6. [Self Service](#self-service)
   - [Adobe Acrobat Pro](#adobe-acrobat-pro)
   - [Adobe Acrobat Pro - Shared Install](#adobe-acrobat-pro---shared-install)
   - [BitLocker Search](#bitlocker-search)
   - [Device Status Check](#device-status-check)
   - [EndNote 21](#endnote-21)
   - [Global Protect](#global-protect)
   - [IBM SPSS 29](#ibm-spss-29)
   - [IBM SPSS 30](#ibm-spss-30)
   - [Microsoft Office 365](#microsoft-office-365)
   - [Mitel Connect](#mitel-connect)
   - [Panopto](#panopto)
   - [PaperCut MF Client](#papercut-mf-client)
   - [PaperCut Print Deploy Client](#papercut-print-deploy-client)
   - [R](#r)
   - [R Studio](#r-studio)
   - [SLU Fonts](#slu-fonts)

# Main

## General Policy
```bash
sudo jamf policy
```
#### Description
Checks for any pending/missing policies and installs them<br />
**Frequency:** `Ongoing`<br />
**Log Location:** `/var/log/jamf.log`

## Enrollment
```bash
sudo jamf policy -event enrollmentComplete
```
#### Description
Checks for any pending/missed policies set to run after a device's enrollment into Jamf<br />
**Frequency:** `Ongoing`<br />
**Log Location:** `/var/log/jamf.log`

## Recon
```bash
sudo jamf recon
```
#### Description
Gathers information about the device and sends its status to Jamf Pro<br />
**Frequency:** `Ongoing`<br />
**Log Location:** `??`

## Update
```bash
sudo jamf policy -event Update
```
#### Description
Checks for missed [enrollment](#Enrollment) policies, [general](#general-policy) policies, runs [recon](#Recon), ensures Rosetta is installed, ensure the device doesn't have mismatched names, and ensures [Jamf Connect](#Jamf-Connect) is installed<br />
**Frequency:** `Ongoing`<br />
**Log Location:** `/var/log/updateInventory.log`<br />
**Self Service Name:** `Update Inventory`
#### Steps
1. [`Maintenance - Check Policy and Update Inventory - Script`](https://github.com/archzaq/Jamf/blob/main/Maintenance/updateInventory.sh)


# Maintenance
## Rename
```bash
sudo jamf policy -event rename
```
#### Description
Prompts the user to choose their department prefix then sets the device name to `Prefix-Serial` using the last six characters of the serial number. If the device name already has a prefix, ask the user if they would like to keep the existing prefix<br />
**Frequency:** `Ongoing`<br />
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
Using a temporary admin account and the logged in user's Secure Token, this policy attempts to fix any issues that may exist with the management account. Ensures the username, password, admin permissions, and Secure Token status of the management account are correct<br />
**Frequency:** `Ongoing`<br />
**Log Location:** `/var/log/management_Fix.log`
#### Steps
1. Create `temp_management` account
2. [`Maintenance - Management Account Fix - Script`](https://github.com/archzaq/Jamf/blob/main/Maintenance/management_Fix.sh)

## Self Service Fix
```bash
sudo jamf policy -event FixSelfService
```
#### Description
Deletes the keychain named after the SPHardwareDataType UUID for each user on the device<br />
**Frequency:** `Ongoing`<br />
**Log Location:** `/var/log/selfService_Fix.log`
#### Steps
1. [`Self Service - Keychain Issues - Script`](https://github.com/archzaq/Jamf/blob/main/Maintenance/selfService_Fix.sh)


# Utilities
## Elevated Account Creation
```bash
sudo jamf policy -event ElevatedAccountCreation
```
#### Description
If a device has been approved for an admin account, this policy will be available. Running this policy will create the local admin account and prompt the currently signed in user for the password to use for the account. If the account already exists, the current user will be asked if they want to delete and recreate the local admin account (forgotten password)<br />
**Frequency:** `Ongoing` - only for those approved to have admin accounts<br />
**Log Location:** `/var/log/elevatedAccount_Creation.log`
#### Steps
1. [`Elevate Account Creation - Script`](https://github.com/archzaq/Jamf/blob/main/Utilities/elevatedAccount_Creation.sh)

## Menu Bar Spacing
```bash
sudo jamf policy -event MenuBarSpacing
```
#### Description
Attempts to reduce the blank space around all the icons in the top right of the menu bar<br />
**Frequency:** `Ongoing`<br />
**Log Location:** `/var/log/menuBar_Spacing.log`
#### Steps
1. [`Menu Bar Spacing - Script`](https://github.com/archzaq/Jamf/blob/main/Utilities/menuBar_Spacing.sh)

## Network Reset
```bash
sudo jamf policy -event NetworkReset
```
#### Description
Attempts to hard reset all network settings of a device, needs work honestly<br />
**Frequency:** `Ongoing`<br />
**Log Location:** `/var/log/networkReset.log`
#### Steps
1. [`Network Reset - Script`](https://github.com/archzaq/Jamf/blob/main/Utilities/network_Reset.sh)

## Secure Token Manager
```bash
sudo jamf policy -event SecureTokenManager
```
#### Description
Run this policy to check Secure Token status for all users on the device. This policy can also be used to add or remove Secure Tokens<br />
**Frequency:** `Ongoing`<br />
**Log Location:** `/var/log/token_Manager.log`
#### Steps
1. Create `temp_management` account
2. [`Secure Token - Token Manager - Script`](https://github.com/archzaq/Jamf/blob/main/Utilities/token_Manager.sh)


# Jamf Connect
## InstallJamfConnect
```bash
sudo jamf policy -event InstallJamfConnect
```
#### Description
Installs the necessary packages for Jamf Connect. The script attempts to ensure all Jamf Connect packages and configuration profiles are installed before continuing. May get stuck during the [recon](#Recon) part of the script<br />
**Frequency:** `Ongoing`<br />
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
Attempts to remove Jamf Connect application, Managed Preferences, Application Support Receipts, Security Agent Login Bundle, and JamfConnect Application Support folder. May get stuck during the [recon](#Recon) part of the script<br />
**Frequency:** `Ongoing`<br />
**Log Location:** `/var/log/JamfConnect_Removal.log`
#### Steps
1. [`Jamf Connect - Removal - Script`](https://github.com/archzaq/Jamf/blob/main/Applications/Jamf%20Connect/JamfConnect_Removal.sh)

## ReinstallJamfConnect
```bash
sudo jamf policy -event ReinstallJamfConnect
```
#### Description
Checks for Jamf Connect Application, Security Bundle, or PLIST file. If found, runs [RemoveJamfConnect](#RemoveJamfConnect), then [InstallJamfConnect](#InstallJamfConnect)<br />
**Frequency:** `Ongoing`<br />
**Log Location:** `/var/log/JamfConnect_Reinstall.log`<br />
**Self Service Name:** `Jamf Connect - Install`
#### Steps
1. [`Jamf Connect - Removal and Reinstall - Script`](https://github.com/archzaq/Jamf/blob/main/Applications/Jamf%20Connect/JamfConnect_Reinstall.sh)

## RepairJamfConnect 
```bash
sudo jamf policy -event RepairJamfConnect
```
#### Description
Installs the necessary packages for Jamf Connect, attempts to set the login screen to use Jamf Connect, then runs [recon](#Recon). Probably useless as [Reinstall](#ReinstallJamfConnect) or [Install](#InstallJamfConnect) generally works. The only addition is running the authchanger command at the end<br />
**Frequency:** `Ongoing`<br />
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
## Cortex 8.8 Install
```bash
sudo jamf policy -event Cortex8.8
```
#### Description
Since I am unable to disable anti-tampering, this policy uninstalls Cortex XDR, attempts to install version 8.8, then attempts to check-in with Cortex. If unable to install Cortex 8.8, attempt to install Cortex 8.5<br />
**Frequency:** `Once per computer`<br />
**Log Location:** `/var/log/cortex_Upgrade.log`
#### Steps
1. [`Cortex XDR - Upgrade - Script`](https://github.com/archzaq/Jamf/blob/main/Applications/Cortex/cortex_Upgrade.sh)

## CyberArk 25.3 Install
```bash
sudo jamf policy -event CyberArkUpdate
```
#### Description
Ensures the management account password isn't the old password, then attempts to install the new package. **WILL ONLY INSTALL** if the management account exists, has the proper password, is an admin, and has a Secure Token<br />
**Frequency:** `Once per computer`<br />
**Log Location:** `/var/log/CyberArk_Update.log`
#### Steps
1. `sudo jamf policy -event CyberArkPWChange`
	- [`CyberArk EPM Agent - Pass Change - Script`](https://github.com/archzaq/Jamf/blob/main/Applications/CyberArk/CyberArk_Update.sh)
2. `sudo jamf policy -event CyberArk25.3`
	- Installs CyberArk 25.3 package

## Rapid7 Install
```bash
sudo jamf policy -event InstallRapid7
```
#### Description
Installs Rapid7 Agent<br />
**Frequency:** `Once per computer`<br />
**Log Location:** `/var/log/jamf.log`
#### Steps
1. Installs one package
	- r7agent.pkg
2. Runs Rapid7 post-install script

# Self Service
## Adobe Acrobat Pro
```bash
sudo jamf policy -event InstallAdobe
```
#### Description
Installs Adobe Acrobat Pro and Creative Cloud<br /> 
**Frequency:** `Ongoing`<br />
**Self Service Name:** `Adobe Acrobat DC`
#### Steps
1. Installs one package
	- macOS (Universal) Adobe Pro - 11-15-24.pkg
2. `sudo jamf recon`

## Adobe Acrobat Pro - Shared Install
```bash
sudo jamf policy -event sharedAdobe
```
#### Description
Installs Adobe Acrobat Pro and Creative Cloud for lab devices. Installing from Self Service also runs `caffeinate -d` so the device doesn't sleep during the long installation<br />
**Frequency:** `Ongoing` - only for Lab devices<br />
**Self Service Name:** `Adobe Application Suite`
#### Steps
1. Installs one package
	- macOS (Universal) - en_US_MACUNIVERSAL.pkg
2. `sudo jamf recon`

## BitLocker Search
```bash
sudo jamf policy -event BitLockerSearch
```
#### Description
RIP - Installs the custom application made for searching through SLU BitLocker files on macOS<br />
**Frequency:** `Ongoing`<br />
**Self Service Name:** `BitLocker Search`
#### Steps
1. Installs one package
	-  BitLocker Search 1.4(1)

## Device Status Check
```bash
sudo jamf policy -event DeviceStatusCheck
```
#### Description
WIP<br />
**Frequency:** `Ongoing` - testing group for now<br />
**Self Service Name:** `Device Status Check`
#### Steps
1. Installs one package
	-  install_DeviceStatusCheck-1.0-SIGNED.pkg

## EndNote 21
```bash
sudo jamf policy -event InstallEndNote
```
#### Description
Installs EndNote 21<br /> 
**Frequency:** `Ongoing`<br />
**Self Service Name:** `EndNote 21`
#### Steps
1. Installs one package
	- EndNote 21

## Global Protect
```bash
sudo jamf policy -event InstallGlobalProtect
```
#### Description
Installs Global Protect 6.2.6<br /> 
**Frequency:** `Ongoing`<br />
**Self Service Name:** `Global Protect`
#### Steps
1. Installs one package
	- GlobalProtect_6.2.6.pkg

## IBM SPSS 29
```bash
sudo jamf policy -event InstallSPSS29
```
#### Description
Installs IBM SPSS 29<br /> 
**Frequency:** `Ongoing`<br />
**Self Service Name:** `IBM SPSS 29`
#### Steps
1. Installs one package
	- SPSSSC_29.0.0.0_Mac.pkg

## IBM SPSS 30
```bash
sudo jamf policy -event InstallSPSS30
```
#### Description
Installs IBM SPSS 30 and automatically ties it to our licensing server<br /> 
**Frequency:** `Ongoing`<br />
**Log Location:** `/var/log/set_SPSSLicense.log`<br />
**Self Service Name:** `IBM SPSS 30`
#### Steps
1. Installs one package
	- SPSS 30
2. [`Set SPSS License`](https://github.com/archzaq/Jamf/blob/main/Applications/SPSS/set_SPSSLicense.sh)

## Microsoft Office 365
```bash
# Capital O for Office 365
sudo jamf policy -event InstallO365
```
#### Description
Installs Microsoft Office 365, includes OneDrive and Teams<br /> 
**Frequency:** `Ongoing`<br />
**Self Service Name:** `Microsoft Office 365`
#### Steps
1. Installs one package
	- Microsoft O365 08-25

## Mitel Connect
```bash
sudo jamf policy -event InstallMitel
```
#### Description
Installs Mitel Connect<br />
**Frequency:** `Ongoing`<br />
**Self Service Name:** `Mitel Connect`
#### Steps
1. Installs one package
	- Mitel Connect7-23.pkg

## Panopto
```bash
sudo jamf policy -event InstallPanopto
```
#### Description
Installs Panopto. The beginning of the Panopto install package name determines the domain the application is linked to<br />
**Frequency:** `Ongoing`<br />
**Self Service Name:** `Panopto`
#### Steps
1. Installs one package
	- domainname_panoptoformac5-18.pkg

## PaperCut MF Client
```bash
sudo jamf policy -event InstallMFClient
```
#### Description
Installs PaperCut MF Client<br />
**Frequency:** `Ongoing`<br />
**Self Service Name:** `PaperCut MF Client`
#### Steps
1. Installs one package
	- MFClient-11-12-24.pkg

## PaperCut Print Deploy Client
```bash
sudo jamf policy -event InstallPrintDeployClient
```
#### Description
Installs PaperCut Print Deploy Client. Devices on Tahoe that install the Print Deploy Client will get the same policy but with an updated driver package<br />
**Frequency:** `Ongoing`<br />
**Self Service Name:** `PaperCut - Print Deploy Client`
#### Steps
1. Installs two packages
	- Kyocera Drivers OS X 10.9+
    - PaperCut Print Deploy Client 6-7
2. `sudo jamf recon`

## R
```bash
sudo jamf policy -event InstallR
```
#### Description
Installs R 4.5.0. The device's architecture will determine which version of R 4.5.0 to install, arm64 or x86_64<br />
**Frequency:** `Ongoing`<br />
**Self Service Name:** `R`
#### Steps
1. Installs one package
	- R-4.5.0-architecture.pkg

## R Studio
```bash
sudo jamf policy -event InstallRStudio
```
#### Description
Installs R Studio 2024.12.1+563<br />
**Frequency:** `Ongoing`<br />
**Self Service Name:** `R Studio`
#### Steps
1. Installs one package
	- RStudio-2024.12.1+563-signed.pkg

## SLU Fonts
```bash
sudo jamf policy -event SLUFonts
```
#### Description
Installs a package of Archivo Narrow and Crimson Pro fonts as well as the SLU logo for AppleScript dialog windows<br />
**Frequency:** `Ongoing`<br />
**Self Service Name:** `SLU Fonts`
#### Steps
1. Installs two packages
	- SLU.icns.pkg
    - SLU_Fonts.pkg


