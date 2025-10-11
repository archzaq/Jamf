#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 09-29-25  ###
### Updated: 10-11-25  ###
### Version: 1.4       ###
##########################

readonly currentUser="${USER:-$(whoami)}"
readonly currentUserHomePath="${HOME:-/home/${currentUser}}"
readonly quantumGRNInstallPath="${PROJECTS:-${currentUserHomePath}}/quantumInstallation"
readonly quantumGRNClonePath="${quantumGRNInstallPath}/QuantumGRN"
readonly quantumGRNTestScriptLocation="${quantumGRNClonePath}/test"
readonly logFile="${currentUserHomePath}/HPC_quantumGRN_Install.log"
readonly condaModule='anaconda/3'

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
        if module avail "$name" 2>&1 | tee -a "$logFile" | grep -q "$name";
        then
            log_Message "Loading module: $name"
            if module load "$name" 2>&1 | tee -a "$logFile";
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
    local prompt="${1:-Would you like to continue?}"
    read -p "${prompt} (Y/N) " answer
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

# Check for sudo privileges
function check_Sudo() {
    groups | grep -qE '\b(wheel|sudo|root)\b';
    return $?
}

# Check for shell env file then source it
function source_ShellEnv() {
    local shellFilesArray=(".bashrc" ".zshrc" ".profile" ".bash_profile")
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
        if ! source_ShellEnv;
        then
            log_Message "Unable to source shell env"
        fi
    fi

    if command -v conda &>/dev/null;
    then
        eval "$(conda shell.bash hook)" 2>/dev/null
        log_Message "Conda initialized successfully"
        log_Message "Conda location: $(which conda)"
    else
        log_Message "Unable to initialize conda after loading module" "WARN"
        log_Message "Attempting to source shell environment files"
        
        if source_ShellEnv;
        then
            if command -v conda &>/dev/null;
            then
                eval "$(conda shell.bash hook)" 2>/dev/null
                log_Message "Conda initialized successfully after sourcing shell files"
            fi
        fi

        if ! command -v conda &>/dev/null;
        then
            log_Message "Unable to locate conda" "ERROR"
            exit 1
        fi
    fi

    log_Message "Checking for myqgrn conda env"
    if conda info --envs 2>&1 | tee -a "$logFile" | grep -q "myqgrn";
    then
        log_Message "Environment myqgrn already exists"
    else
        log_Message "Creating conda environment myqgrn"
        if conda create -n myqgrn python=3.9 -y 2>&1 | tee -a "$logFile";
        then
            log_Message "myqgrn conda env created"
        else
            log_Message "Unable to create myqgrn conda env" "ERROR"
            exit 1
        fi
    fi

    log_Message "Installing cairo and build dependencies via conda"
    if conda install -n myqgrn -c conda-forge cairo pkg-config gcc_linux-64 gxx_linux-64 make -y 2>&1 | tee -a "$logFile";
    then
        log_Message "Installed cairo, pkg-config, and build tools via conda"
    else
        log_Message "Unable to install dependencies via conda" "ERROR"
        exit 1
    fi

    # Fix dependencies Alma/Redhat
    #sudo dnf install -y cairo-devel pkg-config && sudo dnf groupinstall -y 'Development Tools'

    log_Message "Installing QuantumGRN to myqgrn conda env"
    if conda run -n myqgrn pip install --index-url https://test.pypi.org/simple/ --extra-index-url https://pypi.org/simple "QuantumGRN" 2>&1 | tee -a "$logFile";
    then
        log_Message "QuantumGRN successfully installed using pip"
    else
        log_Message "Unable to install QuantumGRN" "ERROR"
        exit 1
    fi

    if ! command -v git &>/dev/null;
    then
        log_Message "Unable to locate git" "WARN"
        if check_Sudo;
        then
            if command -v dnf &>/dev/null;
            then
                if ask_Continue "Would you like to install git using DNF?";
                then
                    if sudo dnf install -y git 2>&1 | tee -a "$logFile";
                    then
                        log_Message "Installed git"
                    else
                        log_Message "Unable to install git" "WARN"
                    fi
                else
                    log_Message "Skipping git install" "WARN"
                fi
            else
                log_Message "Unable to locate DNF for git install" "WARN"
            fi
        else
            log_Message "Unable to install git" "WARN"
        fi
    else
        log_Message "Git already available"
    fi

    if command -v git &>/dev/null;
    then
        if [[ -d "${quantumGRNClonePath}" ]];
        then
            log_Message "QuantumGRN repository already exists"
            log_Message "To update the repo, delete ${quantumGRNClonePath} and run the script again"
        else
            if ask_Continue "Would you like to clone the QuantumGRN repo?";
            then
                log_Message "Cloning QuantumGRN repo"
                if git clone https://github.com/cailab-tamu/QuantumGRN.git "${quantumGRNClonePath}" 2>&1 | tee -a "$logFile";
                then
                    log_Message "QuantumGRN repo cloned to: ${quantumGRNClonePath}"
                else
                    log_Message "Unable to clone QuantumGRN repo" "WARN"
                    log_Message "Try to manually clone from: https://github.com/cailab-tamu/QuantumGRN"
                fi
            else
                log_Message "Skipping repository clone"
            fi
        fi

        if [[ -d "$quantumGRNTestScriptLocation" ]];
        then
            if ask_Continue "Would you like to run the test script (02_example.py)?";
            then
                log_Message "Running test script"
                if cd "$quantumGRNTestScriptLocation";
                then
                    if conda run -n myqgrn python 02_example.py 2>&1 | tee -a "$logFile";
                    then
                        log_Message "Test script ran successfully!"
                    else
                        log_Message "Test script encountered an error" "WARN"
                        log_Message "This may be expected if test data files are missing" "WARN"
                        log_Message "QuantumGRN installation is still complete"
                    fi
                else
                    log_Message "Unable to change to test directory: $quantumGRNTestScriptLocation" "WARN"
                fi
            else
                log_Message "Skipping test script execution"
            fi
        else
            log_Message "Test directory not found" "WARN"
        fi
    else
        log_Message "Git not available, skipping repo clone and test" "WARN"
    fi

    log_Message "QuantumGRN installation completed successfully!"
    log_Message "To use QuantumGRN:"
    log_Message "    conda activate myqgrn"
    log_Message ""
    log_Message "Import qscgrn in Python:"
    log_Message "    from qscgrn import *"
    log_Message ""
    log_Message "Installation location: $quantumGRNInstallPath"
    log_Message "Log file: $logFile"

    exit 0
}

main
