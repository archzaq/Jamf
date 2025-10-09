#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 09-29-25  ###
### Updated: 10-09-25  ###
### Version: 0.4       ###
##########################

readonly currentUser="$(whoami)"
readonly currentUserHomePath="/home/${currentUser}"
readonly quantumGRNInstallPath="${currentUserHomePath}/quantumInstallation"
readonly quantumGRNTestScriptLocation="${quantumGRNInstallPath}/QuantumGRN/test"
readonly logFile="${currentUserHomePath}/HPC_quantumGRN_Install.log"
readonly anacondaLink='https://repo.anaconda.com/archive/Anaconda3-2025.06-0-Linux-x86_64.sh'
readonly anacondaInstallerName='Anaconda3-2025.06-0-Linux-x86_64.sh'
readonly anacondaInstallPath="${currentUserHomePath}/anaconda3"

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
        if mkdir -p "$quantumGRNInstallPath";
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

# Check for shell env file then source it
function source_ShellEnv() {
    local shellFilesArray=(".bashrc" ".zshrc" ".bash_profile")
    for file in "${shellFilesArray[@]}";
    do
        if [[ -f "${currentUserHomePath}/${file}" ]];
        then
            source "${currentUserHomePath}/${file}" 2>/dev/null
            log_Message "Sourced ${file}"
            return 0
        fi
    done
    log_Message "Unable to find shell source file"
    return 1
}

function main() {
    printf "Log: $(date "+%F %T") Beginning HPC QuantumGRN Install script\n" | tee "$logFile"

    if ! create_InstallDir;
    then
        log_Message "Exiting at QuantumGRN folder creation" "ERROR"
        exit 1
    fi

    if ! load_Module "$condaModule";
    then
        log_Message "Attempting to install Anaconda3"
        if curl -L "$anacondaLink" -o "$quantumGRNInstallPath/$anacondaInstallerName";
        then
            log_Message "Anaconda3 installer script downloaded"
            bash "$quantumGRNInstallPath/${anacondaInstallerName}"
        else
            log_Message "Unable to download Anaconda3 installer script" "ERROR"
            exit 1
        fi

        if ! source_ShellEnv;
        then
            log_Message "Unable to source shell env"
        fi
        eval "$(${anacondaInstallPath}/bin/conda shell.bash hook)"
    fi

    log_Message "Checking for conda command"
    if command -v conda &>/dev/null;
    then
        log_Message "Conda available"
    else
        log_Message "Conda not available" "ERROR"
        exit 1
    fi

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

    log_Message "Installing QuantumGRN to myqgrn conda env"
    if conda run -n myqgrn pip install --index-url https://test.pypi.org/simple/ --extra-index-url https://pypi.org/simple "QuantumGRN";
    then
        log_Message "QuantumGRN successfully installed using pip"
    else
        log_Message "Unable to install QuantumGRN" "ERROR"
        exit 1
    fi

    if ! load_Module "$gitModule";
    then
        if sudo dnf install -y git;
        then
            log_Message "Installed git"
        else
            log_Message "Unable to install git"
            exit 1
        fi
    fi

    log_Message "Cloning QuantumGRN repo for example script"
    if git clone https://github.com/cailab-tamu/QuantumGRN.git "${quantumGRNInstallPath}/QuantumGRN";
    then
        log_Message "QuantumGRN repo cloned to \"$quantumGRNInstallPath\""
        if [[ -d "$quantumGRNTestScriptLocation" ]];
        then
            if cd "$quantumGRNTestScriptLocation";
            then
                if conda run -n myqgrn python 02_example.py;
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
    else
        log_Message "Unable to clone QuantumGRN repo: https://github.com/cailab-tamu/QuantumGRN" "ERROR"
        exit 1
    fi

    log_Message "Exiting!"
    exit 0
}

main
