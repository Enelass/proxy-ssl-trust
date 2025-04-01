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
#  LAST RELEASE DATE: 01-Apr-2025                                                  #
#  VERSION: 0.3                                                                    #
#  REVISION: Syntax & Logging improvement +  addition of Intermediate CAs scanning #
#                                                                                  #
#                                                                                  #
####################################################################################

################################# Variables ########################################
version=0.3


# If this is a standalone execution...
if [[ -z ${logI-} ]]; then source ./stderr_stdout_syntax.sh; source ./play.sh; fi


#################################  Functions ########################################
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

# Function to remove stdout and stderr for every cert but the summary of it
quiet() {
    quiet=1
    exec 3>&1 4>&2
    exec 1>/dev/null 2>&1
}

# Function to add back stdout and stderr
unquiet() {
    exec 1>&3 2>&4
    exec 3>&- 4>&-
}

# Function to remove stdout and stderr for everything...
silent() {
    quiet; silent=1
}

intermediate() {
    intermediate=1
}



###########################   Script SWITCHES   ###########################
# Switches and Executions for the initial call (regardless of when)
while [[ $# -gt 0 ]]; do
  case $1 in
    --help|-h) help ;;
    --quiet|-q) quiet ;;
    --silent|-q) silent ;;
    --intermediate|-i) intermediate ;;
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
fi

# 1. Function to export a list of Internal Root CAs from the MacOS Keychain Manager
keychainRootCA() {
    local CAList
    output=$(security find-certificate -a | grep 'labl' | grep -v "com.apple")
    unset CAList; log "Info    - Inspecting MacOS Keychain to find internal Root Certificate Authorities with ability to sign other certificates..." 
    echo '-------------------------------------------------------------------------------------------'
    while read -r line; do # Reading one certificate at the time and verifying if it is a RootCA or not... (Intermediate CA and signed certificates are excluded)
        currentcertname=$(echo $line | cut -d\" -f4)
        currentcertsubj=$(security find-certificate -c "$currentcertname" | grep '"subj"<blob>')
        currentcertissu=$(security find-certificate -c "$currentcertname" | grep '"issu"<blob>')
        if [[ ${currentcertsubj#*=} == ${currentcertissu#*=} ]]; then
            logI "\""$currentcertname"\" is not signed by any other certificates, it is either self-signed or is a RootCA"
            if is_signing_ca "$currentcertname"; then CAList+="$currentcertname"$'\n'; fi
        else
            logI "Certificate: \""$currentcertname"\" is not a RootCA, it's signed by another issuer then itself. This could be a certificate or Intermediate CA..."
        fi
        echo '-------------------------------------------------------------------------------------------'
    done <<< "$output"

    # Removing duplicate from the signing Root CA certificates list
    CAList=$(echo $CAList | sort | uniq) 

    # We want to see the summary
    CAList=$(echo "$CAList" | grep -v '^\s*$') # Remove empty lines...
    if [[ -n "${quiet}" && -z "${silent-}" ]]; then unquiet; fi
    echo -e "-------------------------------------------------------------------------------------------\n\nThe below is a list of Internal Root CAs with the ability to sign other certificate:\nThese are most likely used to sign internal servers or to perform SSL Forward Inspection (MITM)\n\n$CAList"    
}

keychainIntCA() {
    output=$(security find-certificate -a | grep 'labl' | grep -v "com.apple")
    unset CAList; logI "Inspecting MacOS Keychain to find internal Certificate Authorities (Intermediate and Root) with ability to sign other certificates..." 
    echo '-------------------------------------------------------------------------------------------'
    while read -r line; do # Reading one certificate at the time and verifying if it is a RootCA or not... (Intermediate CA and signed certificates are excluded)
        currentcertname=$(echo $line | cut -d\" -f4)
        currentcertsubj=$(security find-certificate -c "$currentcertname" | grep '"subj"<blob>')
        currentcertissu=$(security find-certificate -c "$currentcertname" | grep '"issu"<blob>')
        if is_signing_ca "$currentcertname"; then CAList+="$currentcertname"$'\n'; fi
    done <<< "$output"

    # Removing duplicate from the signing Root CA certificates list
    CAList=$(echo $CAList | sort | uniq)

    # We want to see the output
    CAList=$(echo "$CAList" | grep -v '^\s*$') # Remove empty lines...
    if [[ -n "${quiet}" && -z "${silent-}" ]]; then unquiet; fi
    echo -e "-------------------------------------------------------------------------------------------\n\nThe below is a list of Internal Root CAs with the ability to sign other certificate:\nThese are most likely used to sign internal servers or to perform SSL Forward Inspection (MITM)\n\n$CAList"
}

# 2. Function to check if a certificate is a Signing CA
function is_signing_ca {
    local base64_cert=$1
    # Extract Basic Constraints and Key Usage extensions
    local basic_constraints=$(openssl x509 -in <(security find-certificate -c "$base64_cert" -p) -text -noout | grep -A 1 "X509v3 Basic Constraints" | grep 'CA:TRUE')
    local key_usage=$(openssl x509 -in <(security find-certificate -c "$base64_cert" -p) -text -noout | grep -A 1 'X509v3 Key Usage' | tail -n 1)
    # Check if CA:TRUE is present in Basic Constraints
    if [[ "$basic_constraints" == *"CA:TRUE"* ]]; then
        # Check if Certificate Sign is present in Key Usage
        if [[ "$key_usage" == *"Certificate Sign"* ]]; then
            logS "$base64_cert has X509v3 Basic Constraints set to CA:TRUE and Key Usage set to Certificate Sign. It is a \"signing\" CA"
            return 0
        else
            logI "$base64_cert has X509v3 Basic Constraints set to CA:TRUE but Key Usage is \"not\" set to Certificate Sign. It isn't a signing CA"
            return 1
        fi
    else
        logI "$base64_cert does not have X509v3 Basic Constraints set to CA:TRUE, hence it isn't a Certificate Authority"
        return 1
    fi
}


### Requirement:
logI "Verifying System requirements..."
# Check if the operating system is Darwin (macOS)
if [ "$(uname)" != "Darwin" ]; then log "Error   - This Script is meant to run on macOS, not on: $(uname -v)"; exit 1; fi
logI "     Running on $(get_macos_version)"

if [[ -z ${intermediate-} ]]; then
    keychainRootCA      # Root CAs only
else
    keychainIntCA       # Root and Intermediate CAs
fi

if [[ -n "${silent-}" ]]; then unquiet; fi