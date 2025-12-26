# Jamf Pro Management

A collection of bash scripts for macOS device management through Jamf Pro, created for enterprise deployment

## Repository Structure

### Applications
Scripts for managing enterprise applications:
- [**Adobe**](https://github.com/archzaq/Jamf/tree/main/Applications/Adobe) - Acrobat installation, uninstallation, and troubleshooting
- [**Cortex**](https://github.com/archzaq/Jamf/tree/main/Applications/Cortex) - Endpoint security upgrades and management
- [**CyberArk**](https://github.com/archzaq/Jamf/tree/main/Applications/CyberArk) - Privileged access management deployment
- [**Jamf Connect**](https://github.com/archzaq/Jamf/tree/main/Applications/Jamf%20Connect) - Identity management and deployment
- [**SPSS**](https://github.com/archzaq/Jamf/tree/main/Applications/SPSS) - License server configuration

### Maintenance
Core device management utilities:
- [**Computer Renaming**](https://github.com/archzaq/Jamf/blob/main/Maintenance/ComputerRenameMENU.sh) - Automated and interactive device naming tools
- [**Management Account Fix**](https://github.com/archzaq/Jamf/blob/main/Maintenance/management_Fix.sh) - Account configuration and repair utilities
- [**Inventory Updates**](https://github.com/archzaq/Jamf/blob/main/Maintenance/updateInventory.sh) - Policy execution and system checks
- [**Self Service Fix**](https://github.com/archzaq/Jamf/blob/main/Maintenance/selfService_Fix.sh) - User-facing application fixes

### Utilities
Administrative and troubleshooting tools:
- [**Elevated Account Creation**](https://github.com/archzaq/Jamf/blob/main/Utilities/elevatedAccount_Creation.sh) - Secure admin account provisioning
- [**Secure Token Manager**](https://github.com/archzaq/Jamf/blob/main/Utilities/token_Manager.sh) - Volume ownership and token management
- [**File Search**](https://github.com/archzaq/Jamf/blob/main/Utilities/file_Search.sh) - File location tool
- [**Network Reset**](https://github.com/archzaq/Jamf/blob/main/Utilities/network_Reset.sh) - Network configuration troubleshooting

### Info
Documentation and reference materials:
- [Apple Configurator reset procedures](https://github.com/archzaq/Jamf/blob/main/Info/AppleConfigurator-Reset.md)
- [Jamf Pro enrollment troubleshooting](https://github.com/archzaq/Jamf/blob/main/Info/Enrollment-Issues.md)
- [Command reference guide](https://github.com/archzaq/Jamf/blob/main/Info/Jamf-Commands.md)

### Misc
Specialized tools and archived scripts:
- QuantumGRN installation (HPC and local)
- Legacy maintenance scripts

## Usage

Most scripts are designed to be deployed through Jamf Pro policies but some can also be run locally with appropriate permissions.

## Requirements

- macOS (tested on macOS 12-15)
- Jamf Pro infrastructure (for policy-based deployment)
- Administrative privileges (varies by script)

## Documentation

See [`Info/Jamf-Commands.md`](https://github.com/archzaq/Jamf/blob/main/Info/Jamf-Commands.md) for detailed policy triggers and execution steps.

## Author

Zac Reeves
