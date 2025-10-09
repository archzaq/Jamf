#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 09-29-25  ###
### Updated: 10-08-25  ###
### Version: 0.2       ###
##########################

readonly currentUser="$(whoami)"
readonly currentUserHomePath="/home/${currentUser}"
readonly quantumGRNInstallPath="${currentUserHomePath}/quantumInstallation"
readonly quantumGRNTestScriptLocation="${quantumGRNInstallPath}/QuantumGRN/test"
readonly logFile="${currentUserHomePath}/HPC_quantumGRN_Install.log"
readonly anacondaLink='https://repo.anaconda.com/archive/Anaconda3-2025.06-0-Linux-x86_64.sh'
readonly anacondaInstallerName='Anaconda3-2025.06-0-Linux-x86_64.sh'

### HPC Module Names ###
readonly condaModule="Anaconda3"
readonly gitModule="Git"

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

# Create the installation directory
function create_InstallDir() {
    if [[ ! -d "$quantumGRNInstallPath" ]];
    then
        if mkdir "$quantumGRNInstallPath";
        then
            if [[ -d "$quantumGRNInstallPath" ]];
            then
                log_Message "QuantumGRN install folder created"
            else
                log_Message "Unable to locate QuantumGRN install folder" "WARN"
                return 1
            fi
        else
            log_Message "Unable to create QuantumGRN install folder" "WARN"
            return 1
        fi
    else
        log_Message "QuantumGRN install folder already exists"
    fi
    return 0
}

# Load HPC module if available
function load_Module() {
    local name="$1"
    if command -v module &>/dev/null;
    then
        if module avail "$name" &>/dev/null;
        then
            log_Message "Loading module: $name"
            if module load "$name" &>/dev/null;
            then
                log_Message "Module $name loaded successfully"
                return 0
            else
                log_Message "Failed to load module $name" "WARN"
                return 1
            fi
        else
            log_Message "Module $name not available" "WARN"
            return 1
        fi
    else
        log_Message "Module system not available on this cluster" "WARN"
        return 1
    fi
}

function main() {
    printf "Log: $(date "+%F %T") Beginning HPC QuantumGRN Install script\n" | tee "$logFile"

    # Create install folder
    if ! create_InstallDir;
    then
        log_Message "Exiting at QuantumGRN folder creation" "ERROR"
        exit 1
    fi

    load_Module "$condaModule"

    # Check for conda
    log_Message "Checking for conda command"
    if command -v conda &>/dev/null;
    then
        log_Message "Conda available"
    else
        log_Message "Conda not available" "ERROR"
        if curl -O "$anacondaLink";
        then
            log_Message "Anaconda3 installer script downloaded"
            bash "~/${anacondaInstallerName}"
        else
            log_Message "Unable to download Anaconda3 installer script" "ERROR"
            exit 1
        fi
    fi

    # Initialize conda for bash if needed
    if ! conda info &>/dev/null;
    then
        log_Message "Initializing conda for current shell"
        eval "$(conda shell.bash hook)" 2>/dev/null || true
    fi

    # Make the necessary conda env
    log_Message "Checking for myqgrn conda env"
    if conda info --envs | grep -q "myqgrn";
    then
        log_Message "Environment myqgrn already exists"
    else
        log_Message "Creating conda environment myqgrn"
        if conda create -n myqgrn python=3.9 -y;
        then
            log_Message "myqgrn conda env created"
        else
            log_Message "Unable to create myqgrn conda env" "ERROR"
            exit 1
        fi
    fi

    # Install system dependencies via conda
    log_Message "Installing cairo and build dependencies via conda"
    if conda install -n myqgrn -c conda-forge cairo pkg-config gcc_linux-64 gxx_linux-64 make -y;
    then
        log_Message "Installed cairo, pkg-config, and build tools via conda"
    else
        log_Message "Unable to install dependencies via conda" "ERROR"
        exit 1
    fi

    # Fix dependencies
    #sudo dnf install -y cairo-devel pkg-config
    #sudo dnf groupinstall -y 'Development Tools'

    # Install QuantumGRN
    log_Message "Installing QuantumGRN to myqgrn conda env"
    if conda run -n myqgrn pip install --index-url https://test.pypi.org/simple/ --extra-index-url https://pypi.org/simple "QuantumGRN";
    then
        log_Message "QuantumGRN successfully installed using pip"
    else
        log_Message "Unable to install QuantumGRN" "ERROR"
        exit 1
    fi

    # Try to load git module
    load_Module "$gitModule"

    # Check for git
    log_Message "Checking for git command"
    if ! command -v git &>/dev/null;
    then
        log_Message "Git not available" "ERROR"
        exit 1
    fi

    # Clone QuantumGRN repo for test example
    log_Message "Cloning QuantumGRN repo for example script"
    if git clone https://github.com/cailab-tamu/QuantumGRN.git "${quantumGRNInstallPath}/QuantumGRN";
    then
        log_Message "QuantumGRN repo cloned to \"$quantumGRNInstallPath\""
    else
        log_Message "Unable to clone QuantumGRN repo: https://github.com/cailab-tamu/QuantumGRN" "ERROR"
        exit 1
    fi

    if [[ -d "$quantumGRNTestScriptLocation" ]];
    then
        if cd "$quantumGRNTestScriptLocation";
        then
            if conda run -n myqgrn python 02_test.py;
            then
                log_Message "Test ran successfully!"
            else
                log_Message "Issue with QuantumGRN test" "ERROR"
                exit 1
            fi
        else
            log_Message "Unable to cd to $quantumGRNTestScriptLocation" "ERROR"
            exit 1
        fi
    else
        log_Message "Unable to locate test directory at $quantumGRNTestScriptLocation" "WARN"
    fi

    log_Message "Exiting!"
    exit 0
}

main
