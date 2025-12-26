# Jamf Pro Management

A collection of bash scripts for macOS device management through Jamf Pro, created for enterprise deployment

## Repository Structure

### Applications
Scripts for managing enterprise applications:
- **Adobe** - Acrobat installation, uninstallation, and troubleshooting
- **Cortex** - Endpoint security upgrades and management
- **CyberArk** - Privileged access management deployment
- **Jamf Connect** - Identity management and deployment
- **SPSS** - License server configuration

### Maintenance
Core device management utilities:
- **Computer Renaming** - Automated and interactive device naming tools
- **Management Account** - Account configuration and repair utilities
- **Inventory Updates** - Policy execution and system checks
- **Self Service** - User-facing application fixes

### Utilities
Administrative and troubleshooting tools:
- **Elevated Account Creation** - Secure admin account provisioning
- **Secure Token Manager** - Volume ownership and token management
- **File Search** - File location tool
- **Network Reset** - Network configuration troubleshooting
- **Launch Agent Creator** - Automated daemon deployment

### Info
Documentation and reference materials:
- Apple Configurator reset procedures
- Jamf Pro enrollment troubleshooting
- Command reference guide

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

See `Info/Jamf-Commands.md` for detailed policy triggers and execution steps.

## Author

Zac Reeves
