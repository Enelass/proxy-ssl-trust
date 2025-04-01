#!/bin/zsh

#################### Written by Florian Bidabe #####################################
#                                                                                  #
#  DESCRIPTION: The purpose of this script is to extract a list of internal root   #
#               certificate authorities form the Keychain Manager in MacOS         #
#               To do so, it excludes the certificates found in the Keychain       #
#               manager if there are Intermediate Authorities, Certificates or     #
#               are not signing CAs. It only retain Root and signing CAs and build #
#               a list of it. Each Root CA certificate can then be added to        #
#               certificate stores (e.g. PEM Files) for various clients that are   #
#               not using the MacOS system certificate store (Keychain Manager).   #
#  INITIAL RELEASE DATE: 19-Sep-2024                                               #
#  AUTHOR: Florian Bidabe                                                          #
#  LAST RELEASE DATE: 19-Sep-2024                                                  #
#  VERSION: 0.2                                                                    #
#  REVISION:                                                                       #
#                                                                                  #
#                                                                                  #
####################################################################################
version=0.2

# Function to display the Help Menu
help() {
    clear
    echo -e "Summary: The purpose of this script is to extract a list of internal root certificate authorities form the Keychain Manager in MacOS
         To do so, it excludes the certificates found in the Keychain manager if there are Intermediate Authorities, Certificates or are not signing CAs.
         It only retain Root and signing CAs and build a list of it. Each Root CA certificate can then be added to certificate stores (e.g. PEM Files) for various clients that are not using the MacOS system certificate store (Keychain Manager)."
    echo -e "Author:  florian@photonsec.com.au\t\tgithub.com/Enelass\nRuntime: currently running as $(whoami)\nVervion: $version\n"
    echo -e "Usage: $@ [OPTION]..."
    echo -e "  --help, -h\tDisplay this help menu..."
    echo -e "  --quiet\tQuiet mode when selected, it will store a list of CAs in a variable and only output a summary to stdout."
    echo -e "  --silent\tSilent mode when invoked from another script, it will store a list of CAs in a variable but without any output to stdout/stderr."
    echo -e "  By default, if no switches are specified, it will run standone with verbose information"
    exit 0
}

# Function to remove stdout and stderr
quiet() {
    quiet=1
    exec 3>&1 4>&2
    exec 1>/dev/null 2>&1
}

unquiet() {
    exec 1>&3 2>&4
    exec 3>&- 4>&-
}

silent() {
    quiet; silent=1
}

###########################   Script SWITCHES   ###########################
# Switches and Executions for the initial call (regardless of when)
while [[ $# -gt 0 ]]; do
  case $1 in
    --help|-h) help ;;
    --quiet|-q) quiet ;;
    --silent|-q) silent ;;
   *) ;;
  esac
  shift
done

# If not invoked/sourced by another script, we'll set some variable for standalone use...
if [[ -z "${teefile-}" ]]; then 
    clear
    echo -e "Summary: The purpose of this script is to extract a list of internal root certificate authorities form the Keychain Manager in MacOS
         To do so, it excludes the certificates found in the Keychain manager if there are Intermediate Authorities, Certificates or are not signing CAs.
         It only retain Root and signing CAs and build a list of it. Each Root CA certificate can then be added to certificate stores (e.g. PEM Files)
         for various clients that are not using the MacOS system certificate store (Keychain Manager)."
    echo -e "Author:  florian@photonsec.com.au\t\tgithub.com/Enelass\nRuntime: currently running as $(whoami)"
    echo "This script was invoked directly... Setting variable for standalone use..."
    
    #################################   Variables     ####################################
    AppName="KeychainInternalCAs"
    teefile="/tmp/$AppName.log"
    version=0.2
    ######################################################################################

    ####################################### Defining functions ###########################
    # Logging function
    timestamp() { date "+%Y-%m-%d %H:%M:%S" }
    log() { local message="$1"; echo "$(timestamp) $message" | tee -a $teefile }
    handle_error() { local message="$1"; log "$message"; exit 1 } # Error handling function

    # Function to check if we're running on MacOS
    get_macos_version() { local product_name=$(sw_vers -productName); local product_version=$(sw_vers -productVersion); local build_version=$(sw_vers -buildVersion); echo "$product_name $product_version ($build_version)" }

    # Function to check if a command exists
    command_exists() { command -v "$1" >/dev/null 2>&1 }

    # Function to check if a package is installed via Homebrew
    brew_package_installed() { brew list | grep -qE "^$1$" }

    # Function to attempt installing a package 3x times via Homebrew
    attempt_install() {
        local package="$1"; local attempts=2
        while [ $attempts -gt 0 ]; do
            sudo -u "$user" brew install "$package" > /dev/null
            if [ $? -eq 0 ]; then
                log "$package installed successfully."
                return 0
            fi
            log "Error   - Failed to install $package. Attempts left: $attempts"
            attempts=$((attempts - 1))
        done
        handle_error "Error   - Failed to install $package after 2 attempts. Exiting..."
        exit 1
    }
fi



### Requirement:
log "Info    - Verifying System requirements..."
# Check if the operating system is Darwin (macOS)
if [ "$(uname)" != "Darwin" ]; then log "Error   - This Script is meant to run on macOS, not on: $(uname -v)"; exit 1; fi
log "Info    -      Running on $(get_macos_version)"

# 1. Function to export a list of Internal certificates from the MacOS Keychain Manager
keychainCA() {
    output=$(security find-certificate -a | grep 'labl' | grep -v "com.apple")
    unset IntCAList; log "Info    - Inspecting MacOS Keychain to find internal Root Certificate Authorities with ability to sign other certificates..." 
    echo '-------------------------------------------------------------------------------------------'
    while read -r line; do # Reading one certificate at the time and verifying if it is a RootCA or not... (Intermediate CA and signed certificates are excluded)
        currentcertname=$(echo $line | cut -d\" -f4)
        currentcertsubj=$(security find-certificate -c "$currentcertname" | grep '"subj"<blob>')
        currentcertissu=$(security find-certificate -c "$currentcertname" | grep '"issu"<blob>')
        if [[ ${currentcertsubj#*=} == ${currentcertissu#*=} ]]; then
            log "Info    - \""$currentcertname"\" is not signed by any other certificates, it is either self-signed or is a RootCA"
            #log "Info    - Verifying if \""$currentcertname"\" is a "signing" RootCA..."
            if is_root_ca "$currentcertname"; then IntCAList+="$currentcertname"$'\n'; fi
        else
            log "Info    - Certificate: \""$currentcertname"\" is not a RootCA, it's signed by another issuer then itself. This could be a certificate or Intermediate CA..."
        fi
        echo '-------------------------------------------------------------------------------------------'
    done <<< "$output"

    # Removing duplicate from the signing Root CA certificates list
    IntCAList=$(echo $IntCAList | sort | uniq) 

    # We want to see the output
    if [[ -n "${quiet}" && -z "${silent-}" ]]; then
        unquiet
    fi
    IntCAList=$(echo "$IntCAList" | grep -v '^\s*$') # Remove empty lines...
    echo -e "-------------------------------------------------------------------------------------------\n\nThe below is a list of Internal Root CAs with the ability to sign other certificate:\nThese are most likely used to sign internal servers or to perform SSL Forward Inspection (MITM)\n\n$IntCAList"
}


# 2. Function to check if a certificate is a signing Root CA
function is_root_ca {
    local base64_cert=$1
    # Extract Basic Constraints and Key Usage extensions
    local basic_constraints=$(openssl x509 -in <(security find-certificate -c "$base64_cert" -p) -text -noout | grep -A 1 "X509v3 Basic Constraints" | grep 'CA:TRUE')
    local key_usage=$(openssl x509 -in <(security find-certificate -c "$base64_cert" -p) -text -noout | grep -A 1 'X509v3 Key Usage' | tail -n 1)
    # Check if CA:TRUE is present in Basic Constraints
    if [[ "$basic_constraints" == *"CA:TRUE"* ]]; then
        # Check if Certificate Sign is present in Key Usage
        if [[ "$key_usage" == *"Certificate Sign"* ]]; then
            log "Info    - $base64_cert has X509v3 Basic Constraints set to CA:TRUE and Key Usage set to Certificate Sign. It is a \"signing\" Root CA"
            return 0
        else
            log "Info    - $base64_cert has X509v3 Basic Constraints set to CA:TRUE but Key Usage is \"not\" set to Certificate Sign. It isn't a signing Root CA"
            return 1
        fi
    else
        log "Info    - $base64_cert does not have X509v3 Basic Constraints set to CA:TRUE, hence it isn't a RootCA"
        return 1
    fi
}

keychainCA
if [[ -n "${silent-}" ]]; then
    unquiet
fi