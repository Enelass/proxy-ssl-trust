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
script_dir=$(dirname $(realpath $0))
# If this is a standalone execution...
if [[ -z "${teefile-}" ]]; then AppName="KeychainInternalCAs"; teefile="/tmp/$AppName.log"; fi
if [[ -z "${logI+x}" || -z "${logI}" ]]; then source "$script_dir/stderr_stdout_syntax.sh"; fi

#################################  Functions ########################################
# Function to display the Help Menu
help() {
    clear
    echo -e "Summary: The purpose of this script is to extract a list of internal root certificate authorities form the Keychain Manager in MacOS
         To do so, it excludes the certificates found in the Keychain manager if there are Intermediate Authorities, Certificates or are not signing CAs.
         It only retain signing CAs and build a list of it. Each CA can then be added to certificate stores (e.g. PEM Files) for various clients that are...\n         not using the MacOS system certificate store (Keychain Access)."
    echo -e "Author:  florian@photonsec.com.au\t\tgithub.com/Enelass\nRuntime: currently running as $(whoami)\nVervion: $version\n"
    echo -e "Usage: $@ [OPTION]..."
    echo -e "  --help, -h\t\tDisplay this help menu..."
    echo -e "  --quiet, -q\t\tQuiet mode when selected, it will store a list of ${GREENW}Root${NC} CAs in a variable and only output a summary to stdout."
    echo -e "  --silent, -s\t\tSilent mode when invoked from another script, it will store a list of CAs in a variable but without any output to stdout/stderr."
    echo -e "  --intermediate, -i\tit will return a list of ${GREENW}Intermediate and Root${NC} CAs from KeyChain access. --quiet or --silent can be used on top of it!"
    echo -e "  By default, if no switches are specified, it will run standone with verbose information"
    exit 0
}

# If switch --intermediate was selected, we'll set that value for the runtime
intermediate() { intermediate=1 }


# Function to list MacOS version
get_macos_version() { local product_name=$(sw_vers -productName); local product_version=$(sw_vers -productVersion); local build_version=$(sw_vers -buildVersion); echo "$product_name $product_version ($build_version)" }


# Function to check if a certificate is a Signing CA
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

# Function to list Root CAs from Keychain
keychainRootCA() {
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

# Function to list Intermediate and Root CAs from Keychain
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


###############################   RUNTIME   ################################
# If not invoked/sourced by another script, we'll set some variable for standalone use...
if [[ -z "${invoked-}" ]]; then 
    clear
    echo -e "Summary: The purpose of this script is to extract a list of internal root certificate authorities form the Keychain Manager in MacOS
         To do so, it excludes the certificates found in the Keychain manager if there are Intermediate Authorities, Certificates or are not signing CAs.
         It only retain Root and signing CAs and build a list of it. Each Root CA certificate can then be added to certificate stores (e.g. PEM Files)
         for various clients that are not using the MacOS system certificate store (Keychain Manager)."
    echo -e "Author:  florian@photonsec.com.au\t\tgithub.com/Enelass\nRuntime: currently running as $(whoami)"
    echo "This script was invoked directly... Setting variable for standalone use..."
fi


###########################   Script SWITCHES   ###########################
while [[ $# -gt 0 ]]; do
  case $1 in
    --help|-h) help ;;
    --quiet|-q) quiet ;;
    --silent|-s) silent ;;
    --intermediate|-i) intermediate ;;
   *) ;;
  esac
  shift
done


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