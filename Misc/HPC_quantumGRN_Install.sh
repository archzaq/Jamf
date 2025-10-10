#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 09-29-25  ###
### Updated: 10-10-25  ###
### Version: 1.0       ###
##########################

readonly currentUser="$(whoami)"
readonly currentUserHomePath="/home/${currentUser}"
readonly quantumGRNInstallPath="${PROJECTS:-${currentUserHomePath}}/quantumInstallation"
readonly quantumGRNTestScriptLocation="${quantumGRNInstallPath}/QuantumGRN/test"
readonly logFile="${currentUserHomePath}/HPC_quantumGRN_Install.log"
readonly anacondaLink='https://repo.anaconda.com/archive/Anaconda3-2025.06-0-Linux-x86_64.sh'
readonly anacondaInstallerName='Anaconda3-2025.06-0-Linux-x86_64.sh'
readonly anacondaInstallPath="${currentUserHomePath}/anaconda3"

### HPC Module Names ###
readonly condaModule='anaconda'

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
        if module avail "$name" 2>&1 | grep -q "$name";
        then
            log_Message "Loading module: $name"
            if module load "$name" 2>&1;
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

# Ask to confirm before continuing
function ask_Continue() {
    read -p 'Would you like to continue? (Y/N): ' answer
    case "$answer" in
        [Yy]|[Yy][Ee][Ss])
            log_Message "User chose to continue"
            return 0
            ;;
        *)
            log_Message "User did not continue"
            return 1
            ;;
    esac
}

# Without HPC modules, install anaconda
function linux_InstallAnaconda() {
    log_Message "Attempting to install Anaconda3"
    if curl -L "$anacondaLink" -o "$quantumGRNInstallPath/$anacondaInstallerName";
    then
        log_Message "Anaconda3 installer script downloaded"
        bash "$quantumGRNInstallPath/${anacondaInstallerName}"
    else
        log_Message "Unable to download Anaconda3 installer script" "ERROR"
        return 1
    fi
    return 0
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
        log_Message "Unable to load conda module" "WARN"
        log_Message "Would you like to install Linux Anaconda3?"
        if ask_Continue;
        then
            if ! linux_InstallAnaconda;
            then
                log_Message "Anaconda installation failed" "ERROR"
                exit 1
            fi

            if ! source_ShellEnv;
            then
                log_Message "Unable to source shell env"
            fi

            eval "$(${anacondaInstallPath}/bin/conda shell.bash hook)"
        fi
    fi

    if command -v conda &>/dev/null;
    then
        eval "$(conda shell.bash hook)"
        log_Message "Conda initialized"
    else
        log_Message "Unable to initialize conda" "WARN"
        log_Message "Would you like to try a manual conda initialization?"
        if ask_Continue;
        then
            log_Message "Attempting manual conda initialization"
            if [[ -f "${anacondaInstallPath}/etc/profile.d/conda.sh" ]];
            then
                source "${anacondaInstallPath}/etc/profile.d/conda.sh"
            fi

            if ! command -v conda &>/dev/null;
            then
                log_Message "Unable to locate conda" "ERROR"
                exit 1
            fi
        else
            log_Message "Skipping manual conda initialization" "WARN"
            log_Message "Unable to continue without conda" "ERROR"
            exit 1
        fi
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

    if ! command -v git &>/dev/null;
    then
        log_Message "Unable to locate git" "WARN"
        log_Message "Would you like to install git using DNF? Requires sudo access"
        if ask_Continue;
        then
            if command -v dnf &>/dev/null;
            then
                if sudo dnf install -y git;
                then
                    log_Message "Installed git"
                else
                    log_Message "Unable to install git" "WARN"
                fi
            else
                log_Message "Unable to locate DNF" "WARN"
            fi
        else
            log_Message "Skipping git install" "WARN"
        fi
    else
        log_Message "Git already available"
    fi

    if command -v git &>/dev/null;
    then
        if [[ ! -d "${quantumGRNInstallPath}/QuantumGRN" ]];
        then
            log_Message "Would you like to clone QuantumGRN repo for test script?"
            if ask_Continue;
            then
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
                                log_Message "Issue with QuantumGRN test" "WARN"
                            fi
                        else
                            log_Message "Unable to cd to $quantumGRNTestScriptLocation" "WARN"
                        fi
                    else
                        log_Message "Unable to locate test directory at $quantumGRNTestScriptLocation" "WARN"
                    fi
                else
                    log_Message "Unable to clone QuantumGRN repo: https://github.com/cailab-tamu/QuantumGRN" "WARN"
                fi
            else
                log_Message "Skipping QuantumGRN repo cloning"
            fi
        else
            log_Message "QuantumGRN repo already cloned"
        fi
    else
        log_Message "Git not found" "WARN"
    fi

    log_Message "QuantumGRN installation completed successfully!"
    log_Message "To use QuantumGRN:"
    log_Message "    Activate the environment: conda activate myqgrn"
    log_Message "    Import QuantumGRN in your Python scripts"
    log_Message ""
    log_Message "Installation location: $quantumGRNInstallPath"
    log_Message "Log file: $logFile"
    exit 0
}

main
