#!/bin/bash

##########################
### Author: Zac Reeves ###
### Created: 08-01-25  ###
### Updated: 08-05-25  ###
### Version: 1.2       ###
##########################

readonly defaultIconPath='/usr/local/jamfconnect/SLU.icns'
readonly genericIconPath='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Everyone.icns'
effectiveIconPath="$defaultIconPath"
readonly dialogTitle='QuantumGRN Installation'
readonly deviceArch="$(/usr/bin/uname -m)"
readonly deviceShell="$(echo $SHELL | awk -F "/" '{print $NF}')"
readonly currentUser="$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/  { print $3 }')"
readonly currentUserHomePath="/Users/${currentUser}"
readonly quantumGRNInstallPath="${currentUserHomePath}/quantumInstallation"
readonly logFile="${quantumGRNInstallPath}/quantumGRN_Install.log"
readonly tweedledumInstallPath="${quantumGRNInstallPath}/tweedledum"
readonly tweedledumCMakeListsFile="${tweedledumInstallPath}/CMakeLists.txt"
readonly abcesopCMakeListsFile="${tweedledumInstallPath}/external/abcesop/CMakeLists.txt"
readonly abcsatCMakeListsFile="${tweedledumInstallPath}/external/abcsat/CMakeLists.txt"
readonly pybind11CMakeListsFile="${tweedledumInstallPath}/external/pybind11/CMakeLists.txt"
readonly homebrewPKGLink='https://github.com/Homebrew/brew/releases/download/4.5.13/Homebrew-4.5.13.pkg'
readonly homebrewPKGName='Homebrew-4.5.13.pkg'
readonly homebrewPKGFullPath="${quantumGRNInstallPath}/${homebrewPKGName}"
readonly anacondaLink='https://repo.anaconda.com/archive/'
readonly anacondaName="Anaconda3-2025.06-0-MacOSX-${deviceArch}.sh"
readonly anacondaInstallPath="${currentUserHomePath}/anaconda3"
readonly tweedledumPyprojectFile="${tweedledumInstallPath}/pyproject.toml"
readonly cmakeListsArray=("$tweedledumCMakeListsFile" "$abcesopCMakeListsFile" "$abcsatCMakeListsFile" "$pybind11CMakeListsFile")
readonly brewArray=("python@3.9" "cmake" "pkg-config" "cairo")
readonly anacondaSiliconSHA='195f234204e2f18803cea38bbebefcaac5a3d8d95e2e4ee106d1b87b23b9fc4a'
readonly anacondaIntelSHA='8625a155ff1d2848afa360e70357e14c25f0ac7ac21e4e4bf15015bc58b08d06'
readonly homebrewPKGSHA='949ea05272138dbce60439a37d059a80fceab833553767751cc516ebeabc1d4c'

# Append current status to log file
function log_Message() {
    local timestamp="$(date "+%F %T")"
    printf "Log: %s %s\n" "$timestamp" "$1" | tee -a "$logFile"
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
                log_Message "ERROR: Unable to locate QuantumGRN install folder"
                return 1
            fi
        else
            log_Message "ERROR: Unable to create QuantumGRN install folder"
            return 1
        fi
    else
        log_Message "QuantumGRN install folder already exists"
    fi
    return 0
}

# Check for valid icon file, AppleScript dialog boxes will error without it
function icon_Check() {
    if [[ ! -f "$effectiveIconPath" ]];
    then
        log_Message "No SLU icon found"
        if [[ -f "$genericIconPath" ]];
        then
            log_Message "Generic icon found"
            effectiveIconPath="$genericIconPath"
        else
            log_Message "Generic icon not found"
            return 1
        fi
    fi
    return 0
}

# Install Xcode CLI tools
function install_XCodeCLI() {
    if xcode-select -p &>/dev/null;
    then
        log_Message "Xcode command line tools installed"
    else
        log_Message "Xcode command line tools not found"
        if binary_Dialog "Xcode command line tools are required.\n\nWould you like to install them?" "Install";
        then
            xcode-select --install &>/dev/null
            log_Message "Please complete the Xcode installation and re-run this script"
            alert_Dialog "Please complete the Xcode installation and re-run this script."
            exit 0
        else
            log_Message "Cannot proceed without Xcode command line tools"
            alert_Dialog "Cannot proceed without Xcode command line tools."
            return 1
        fi
    fi
    return 0 
}

# Check for Homebrew and install if unavailable
function install_HomebrewPKG() {
    if [[ "$deviceArch" == 'arm64' ]];
    then
        homebrewPrefix='/opt/homebrew'
    else
        homebrewPrefix='/usr/local'
    fi
    
    if command -v brew &>/dev/null;
    then
        log_Message "Homebrew installed"
    else
        log_Message "Homebrew not found"
        log_Message "Sourcing shell env to check for brew"
        if ! source_ShellEnv;
        then
            log_Message "Unable to source shell env file"
        fi
        
        if [[ -f "${homebrewPrefix}/bin/brew" ]];
        then
            log_Message "Attempting to eval brew path"
            if eval "$(${homebrewPrefix}/bin/brew shellenv)" 2>/dev/null;
            then
                log_Message "Successfully ran eval on brew path"
            else
                log_Message "Failed to eval brew path"
            fi
        else
            log_Message "Unable to find brew"
        fi
        
        if ! command -v brew &>/dev/null;
        then
            log_Message "Prompting to install: \"$homebrewPKGName\""
            if binary_Dialog "Would you like to install:\n\n${homebrewPKGName}" "Install";
            then
                log_Message "Curling \"$homebrewPKGLink\" to \"$homebrewPKGFullPath\""
                if curl -L "$homebrewPKGLink" -o "$homebrewPKGFullPath";
                then
                    log_Message "PKG successfully downloaded to \"$quantumGRNInstallPath\""
                    if printf "%s  %s\n" "$homebrewPKGSHA" "$homebrewPKGFullPath" | /usr/bin/shasum -a 256 --check --quiet;
                    then
                        log_Message "Homebrew PKG verified successfully"
                        log_Message "Installing PKG"
                        open -W "$homebrewPKGFullPath"
                    else
                        log_Message "ERROR: Unable to verify Homebrew PKG integrity"
                        alert_Dialog "Unable to verify Homebrew PKG integrity"
                        return 1
                    fi
                else
                    log_Message "PKG not installed, using web instead"
                    log_Message "After install, quit Safari to continue"
                    open -W -n "$homebrewPKGLink"
                fi
            else
                log_Message "Cannot proceed without Homebrew"
                alert_Dialog "Cannot proceed without Homebrew.\n\nExiting!"
                return 1
            fi
        else
            log_Message "Homebrew found"
        fi
    fi
    
    eval "$(${homebrewPrefix}/bin/brew shellenv)"
    
    if ! command -v brew &>/dev/null;
    then
        log_Message "ERROR: Unable to locate Homebrew"
        alert_Dialog "Unable to locate Homebrew"
        return 1
    fi
    return 0
}

# Check for Conda and install if unavailable
function install_Conda() {
    if command -v conda &>/dev/null;
    then
        log_Message "Conda installed"
    else
        log_Message "Conda not installed"
        if [[ ! -d "$anacondaInstallPath" ]];
        then
            log_Message "Prompting to install: \"$anacondaName\""
            if binary_Dialog "Would you like to install:\n\n${anacondaName}" "Install";
            then
                if curl -L "$anacondaLink/$anacondaName" -o "$quantumGRNInstallPath/$anacondaName";
                then
                    log_Message "Successfully downloaded anaconda"
                    if [[ "$deviceArch" == 'arm64' ]];
                    then
                        expectedSHA="$anacondaSiliconSHA"
                    else
                        expectedSHA="$anacondaIntelSHA"
                    fi
                    if printf "%s  %s\n" "$expectedSHA" "$quantumGRNInstallPath/$anacondaName" | /usr/bin/shasum -a 256 --check --quiet;
                    then
                        log_Message "Running anaconda setup"
                        bash "$quantumGRNInstallPath/$anacondaName"
                        ${anacondaInstallPath}/bin/conda init
                        if ! source_ShellEnv;
                        then
                            log_Message "Unable to source shell env"
                        fi
                        eval "$(${anacondaInstallPath}/bin/conda shell.${deviceShell} hook)"
                    else
                        log_Message "ERROR: Unable to verify Anaconda file integrity"
                        alert_Dialog "Unable to verify Anaconda file integrity"
                        return 1
                    fi
                else
                    log_Message "ERROR: Unable to download anaconda"
                    alert_Dialog "Unable to download anaconda."
                    return 1
                fi
            else
                log_Message "Cannot proceed without Anaconda"
                alert_Dialog "Cannot proceed without Anaconda.\n\nExiting!"
                return 1
            fi
        else
            log_Message "Anaconda3 install directory already exists at \"$anacondaInstallPath\""
            log_Message "Attempting to initialize conda"
            if ! start_CondaEnv;
            then
                log_Message "ERROR: Unable to initialize existing conda installation"
                alert_Dialog "Unable to initialize existing conda installation"
                return 1
            fi
        fi
    fi
    return 0
}

# Download tweedledum version 1.1.1
function download_Tweedledum() {
    if [[ ! -d "$tweedledumInstallPath" ]];
    then
        if git clone --branch v1.1.1 --depth 1 https://github.com/boschmitt/tweedledum.git "$tweedledumInstallPath";
        then
            log_Message "Tweedledum 1.1.1 downloaded to: \"$tweedledumInstallPath\""
            if [[ ! -d "$tweedledumInstallPath" ]];
            then
                log_Message "ERROR: Unable to locate Tweedledum directory"
                return 1
            fi
        else
            if command -v git &>/dev/null;
            then
                log_Message "ERROR: Unable to download Tweedledum 1.1.1"
                alert_Dialog "Unable to download Tweedledum 1.1.1"
            else
                log_Message "ERROR: Missing git"
                alert_Dialog "Missing git"
            fi
            return 1
        fi
    else
        log_Message "Tweedledum install directory already exists at \"$tweedledumInstallPath\""
        if ! grep -q 'return "1.1.1"' "${tweedledumInstallPath}/setup.py";
        then
            log_Message "Unsure of Tweedledum version"
            alert_Dialog "Tweedledum install directory already exists at ${tweedledumInstallPath}.\n\nRemove this folder and rerun the script to continue."
            return 1
        else
            log_Message "Tweedledum version 1.1.1 present"
        fi
    fi
    return 0
}

# Ensure Xcode CLI tools, Homebrew, and Anaconda are installed
function preCheck_Device() {
    if ! install_XCodeCLI;
    then
        return 1
    fi
    
    if ! install_HomebrewPKG;
    then
        return 1
    fi
    
    if ! install_Conda;
    then
        return 1
    fi
    
    if ! download_Tweedledum;
    then
        return 1
    fi
    
    return 0
}

# Edit tweedledum requirements since it wont install otherwise
function edit_TweedledumFiles() {
    if [[ -f "$tweedledumPyprojectFile" ]];
    then
        if grep -q '^\[project\]' "$tweedledumPyprojectFile";
        then
            log_Message "Removing [project] section from: \"$tweedledumPyprojectFile\""
            sed -i '' -e '/^\[project\].*/d' "$tweedledumPyprojectFile"
        fi
        
        if grep -q '^requires-python = ' "$tweedledumPyprojectFile";
        then
            log_Message "Removing requires-python line from: \"$tweedledumPyprojectFile\""
            sed -i '' -e '/^requires-python = .*/d' "$tweedledumPyprojectFile"
        fi
    else
        log_Message "ERROR: Unable to locate: \"$tweedledumPyprojectFile\""
        alert_Dialog "Unable to locate ${tweedledumPyprojectFile}"
        return 1
    fi
    
    for file in "${cmakeListsArray[@]}";
    do
        if [[ -f "$file" ]];
        then
            if grep -q '^cmake_minimum_required(VERSION 3.5...3.27)' "$file";
            then
                log_Message "CMake minimum for \"$file\" already valid"
            else
                log_Message "Editing cmake minimum for \"$file\""
                sed -i '' -e 's/^cmake_minimum_required.*/#&/' "$file"
                sed -i '' -e '/^#cmake_minimum_required.*/a\
cmake_minimum_required(VERSION 3.5...3.27)' "$file"
            fi
        else
            log_Message "ERROR: Unable to locate \"$file\""
            alert_Dialog "Unable to locate ${file}.\n\nCheck Tweedledum version."
            return 1
        fi
    done
    return 0
}

# Install necessary brew packages to edit and install tweedledum
function brew_PackageInstall() {
    if command -v brew &>/dev/null;
    then
        for package in "${brewArray[@]}";
        do
            if brew list "$package" &>/dev/null;
            then
                log_Message "Skipping \"$package\", already installed"
            else
                log_Message "Installing $package"
                if brew install "$package";
                then
                    log_Message "$package installed"
                else
                    log_Message "ERROR: Unable to install $package"
                    alert_Dialog "Unable to install:\n\n${package}"
                    return 1
                fi
            fi
        done
    else
        log_Message "ERROR: Missing brew command"
        alert_Dialog "Missing brew command."
        return 1
    fi
    return 0
}

# Check for Anaconda and initialize
function start_CondaEnv() {
    if [[ -d "$anacondaInstallPath" ]];
    then
        eval "$(${anacondaInstallPath}/bin/conda shell.${deviceShell} hook)"
        if ! command -v conda &>/dev/null;
        then
            ${anacondaInstallPath}/bin/conda init
            if ! command -v conda &>/dev/null;
            then
                log_Message "ERROR: Missing conda command"
                alert_Dialog "Missing conda command."
                return 1
            else
                log_Message "Found conda command after conda init"
            fi
        else
            log_Message "Found conda command"
        fi
    else
        log_Message "ERROR: Unable to locate Anaconda installation"
        alert_Dialog "Unable to locate Anaconda installation."
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

# AppleScript - Informing the user and giving them two choices
function binary_Dialog() {
    local promptString="$1"
    local mainButton="$2"
    local count=1
    while [ $count -le 10 ];
    do
        binDialog=$(/usr/bin/osascript <<OOP
        try
            set promptString to "$promptString"
            set mainButton to "$mainButton"
            set iconPath to "$effectiveIconPath"
            set dialogTitle to "$dialogTitle"
            set dialogResult to display dialog promptString buttons {"Cancel", mainButton} default button mainButton with icon POSIX file iconPath with title dialogTitle giving up after 900
            set buttonChoice to button returned of dialogResult
            if buttonChoice is equal to "" then
                return "timeout"
            else
                return buttonChoice
            end if
        on error
            return "Cancel"
        end try
OOP
        )
        case "$binDialog" in
            'Cancel')
                log_Message "User responded with: \"$binDialog\""
                return 1
                ;;
            'timeout' | '')
                log_Message "No response, re-prompting ($count/10)"
                ((count++))
                sleep 1
                ;;
            *)
                log_Message "User responded with: \"$binDialog\""
                return 0
                ;;
        esac
    done
    return 1
}

# AppleScript - Create alert dialog window
function alert_Dialog() {
    local promptString="$1"
    log_Message "Displaying alert dialog"
    alertDialog=$(/usr/bin/osascript <<OOP
    try
        set promptString to "$promptString"
        set choice to (display alert promptString as critical buttons "OK" default button 1 giving up after 900)
        if (gave up of choice) is true then
            return "Timeout"
        else
            return (button returned of choice)
        end if
    on error
        return "Error"
    end try
OOP
    )
    case "$alertDialog" in
        'Error')
            log_Message "Unable to show alert dialog"
            ;;
        'Timeout')
            log_Message "Alert timed out"
            ;;
        *)
            log_Message "Continued through alert dialog"
            ;;
    esac
}

function main() {
    /usr/bin/caffeinate -d &
    caffeinatePID=$!
    trap "kill $caffeinatePID" EXIT
    
    if ! create_InstallDir;
    then
        printf "Log: $(date "+%F %T") Exiting at quantum folder creation\n"
        exit 1
    fi

    printf "Log: $(date "+%F %T") Beginning QuantumGRN Install script\n" | tee "$logFile"

    if ! icon_Check;
    then
        log_Message "ERROR: Exiting at icon check"
        exit 1
    fi

    if ! preCheck_Device;
    then
        log_Message "ERROR: Exiting at pre-check"
        exit 1
    fi

    log_Message "Completed pre-checks, starting QuantumGRN installation"

    if ! brew_PackageInstall;
    then
        log_Message "ERROR: Exiting at brew package install"
        exit 1
    fi

    if ! edit_TweedledumFiles;
    then
        log_Message "ERROR: Exiting at tweedledum file editing"
        exit 1
    fi

    log_Message "Checking for conda command"
    if command -v conda &>/dev/null;
    then
        log_Message "Conda available"
    else
        if ! start_CondaEnv;
        then
            log_Message "ERROR: Unable to initialize conda env"
            exit 1
        fi
        
        if ! command -v conda &>/dev/null;
        then
            log_Message "ERROR: Conda still not available"
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
            log_Message "ERROR: Unable to create myqgrn conda env"
            exit 1
        fi
    fi

    log_Message "Installing tweedledum to myqgrn conda env"
    if conda run -n myqgrn pip install "${tweedledumInstallPath}/.";
    then
        log_Message "Tweedledum successfully installed using pip"
    else
        log_Message "ERROR: Unable to install Tweedledum using pip"
        alert_Dialog "Unable to install Tweedledum using pip"
        exit 1
    fi

    log_Message "Installing QuantumGRN to myqgrn conda env"
    if conda run -n myqgrn pip install --index-url https://test.pypi.org/simple/ --extra-index-url https://pypi.org/simple "QuantumGRN";
    then
        log_Message "QuantumGRN successfully installed using pip"
    else
        log_Message "ERROR: Unable to install QuantumGRN"
        alert_Dialog "Unable to install QuantumGRN"
        open "$logFile"
        exit 1
    fi

    log_Message "Installing Spyder for myqgrn conda env"
    if conda run -n myqgrn conda install spyder;
    then
        log_Message "Spyder installed for myqgrn conda env"
    else
        log_Message "ERROR: Unable to install Spyder for myqgrn conda env"
    fi

    log_Message "Cloning QuantumGRN repo for example script"
    if git clone https://github.com/cailab-tamu/QuantumGRN.git "${quantumGRNInstallPath}/QuantumGRN";
    then
        log_Message "QuantumGRN repo cloned to \"$quantumGRNInstallPath\""
    else
        log_Message "ERROR: Unable to clone QuantumGRN repo"
        log_Message "Opening QuantumGRN Github link"
        open -u -n "https://github.com/cailab-tamu/QuantumGRN"
    fi

    if [[ -d "${currentUserHomePath}/Applications/Anaconda-Navigator.app" ]];
    then
        log_Message "Opening \"${currentUserHomePath}/Applications/Anaconda-Navigator.app\""
        open "${currentUserHomePath}/Applications/Anaconda-Navigator.app"
        sleep 25
        if ! binary_Dialog "Ensure you change the Anaconda Navigator environment!\n\nFrom: base (root)\n\nTo: myqgrn\n\nThen launch Spyder." "Done";
        then
            log_Message "Exiting at last dialog"
        fi
    elif [[ -d "/Applications/Anaconda-Navigator.app" ]];
    then
        log_Message "Opening \"/Applications/Anaconda-Navigator.app\""
        open "/Applications/Anaconda-Navigator.app"
        sleep 25
        if ! binary_Dialog "Ensure you change the Anaconda Navigator environment!\n\nFrom: base (root)\n\nTo: myqgrn\n\nThen launch Spyder." "Done";
        then
            log_Message "Exiting at last dialog"
        fi
    else
        log_Message "Unable to locate Anaconda-Navigator.app"
    fi

    log_Message "Exiting!"
    exit 0
}

main
