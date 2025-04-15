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
local scriptname=$(basename $(realpath $0))
local current_dir=$(dirname $(realpath $0))
if [[ -z "${teefile-}" ]]; then AppName="KeychainInternalCAs"; teefile="/tmp/$AppName.log"; fi
if [[ -z ${logI-} ]]; then source "$current_dir/../stderr_stdout_syntax.sh"; fi

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

# Function to check if a certificate is a Signing CA
is_signing_ca () {
    local cert_name=$1
    # Extract Basic Constraints and Key Usage extensions
    local basic_constraints=$(openssl x509 -in <(security find-certificate -c "$cert_name" -p) -text -noout | grep -A 1 "X509v3 Basic Constraints" | grep 'CA:TRUE')
    local key_usage=$(openssl x509 -in <(security find-certificate -c "$cert_name" -p) -text -noout | grep -A 1 'X509v3 Key Usage' | tail -n 1)
    # Check if CA:TRUE is present in Basic Constraints
    if [[ "$basic_constraints" == *"CA:TRUE"* ]]; then
        # Check if Certificate Sign is present in Key Usage
        if [[ "$key_usage" == *"Certificate Sign"* ]]; then
            logS "    It has X509v3 Basic Constraints set to CA:TRUE and Key Usage set to Certificate Sign. It is a \"signing\" CA"
            return 0
        else
            logI "    It has X509v3 Basic Constraints set to CA:TRUE but Key Usage is \"not\" set to Certificate Sign. It isn't a signing CA"
            return 1
        fi
    else
        logI "    It does not have X509v3 Basic Constraints set to CA:TRUE, hence it isn't a Certificate Authority"
        return 1
    fi
}

# Function to verify whether the CA is public or internal
is_internal () {
    local issuer_name="$1"
    if [[ $issuer_name != $currentcertname ]] ; then
        logI "    Verifying if ${BLUEW}$currentcertname${NC} issuer for ${BLUEW}$issuer_name${NC} is internal or not..."
    fi
    # The file /private/etc/ssl/cert.pem on macOS is part of the OpenSSL library. This file typically contains a collection of public root certificates
    if [[ -f "/private/etc/ssl/cert.pem" ]]; then
        base64=$(security find-certificate -c "$1" -p) 2>/dev/null
        if [[ $? -ne 0 ]]; then
            # We don't have have a Base 64 for this Base 64 CA issuer, let's lookup the name as last resort...
            if $(cat "/private/etc/ssl/cert.pem" | grep -q "$issuer_name"); then
                logW "    This is public! skipping this one..."
                return 1
            else
                logI "    This is not public, or it's expired (no longer in public certificate stores)..."
                if $(security find-certificate -a | grep 'labl' | grep -q "$issuer_name"); then
                    logI "    It is internal! We found the issuer in Keychain Access..."
                    return 0
                else
                    logI "    It isn't internal either! skipping..."
                    return 1
                fi
            fi
        else
            if [[ -n $base64 ]]; then
                base64_l3=$(echo "$base64" | awk 'NR == 4') # We only select line 4 as it is less compute intensive and still has a low chance of collision
                # Let's see if our internal signing CA is, or isn't internal...
                if $(cat "/private/etc/ssl/cert.pem" | grep -q "$base64_l3"); then
                    logW "    This is public! skipping this one..."
                    return 1
                else
                    logI "    This is not public, so it's by definition internal..."
                    return 0
                fi
            else
                # If we can't export the Base64 from Keychain Access, let's just carry on and skip the check...
                return 0
            fi
        fi
    else
        # if we can't use a public PEM Certificate store, let's just carry and skip the check...
        return 0
    fi
    unset base64; unset base64_l3
}

# Function to list Root CAs from Keychain
keychainCA() {
    output=$(security find-certificate -a | grep 'labl' | grep -v "com.apple")
    unset CAList; log "Info    - Inspecting MacOS Keychain to find internal Certificate Authorities with ability to sign other certificates..." 
    while read -r line; do # Reading one certificate at the time and verifying if it is a RootCA or not... (Intermediate CA and signed certificates are excluded)
        currentcertname=$(echo $line | cut -d\" -f4)
        currentcertsubj=$(security find-certificate -c "$currentcertname" | grep '"subj"<blob>')
        currentcertissu=$(security find-certificate -c "$currentcertname" | grep '"issu"<blob>')
        logI "Processing \"${PURPLE}"$currentcertname"${NC}\"..."
        if [[ ${currentcertsubj#*=} == ${currentcertissu#*=} ]]; then   # Root
            logI "    It is not signed by any other certificates, it is either self-signed or is a RootCA"
            if is_signing_ca "$currentcertname"; then
                if is_internal "$currentcertname"; then
                    CAList+="$currentcertname"$'\n'
                fi
            fi
        else                                                            # Intermediate of Leaf certificate
            logI "    It is not a RootCA, it's signed by another issuer then itself. This could be a certificate or Intermediate CA..."
            if [[ -n $intermediate ]]; then # If intermediate was selected, we'll process it too...
                logI "    It is not signed by any other certificates, it is either self-signed or is a RootCA"
                if is_signing_ca "$currentcertname"; then
                    # We need to find the issuer to we can assess whether the issuer is public or not
                    # Using the intermediate CA name would not work, since intermediate public CA are "not" listed in public Certificate Stores (only the Root CAs are...)
                    # We'll only process "signing intermediate" to save on compute / performance
                    local b64_issuer=$(openssl x509 -in <(security find-certificate -c "$currentcertname" -p) -noout -issuer | awk -F 'CN=' '{print $2}' | awk -F ',' '{print $1}')
                    if [[ -n $b64_issuer ]]; then
                        # We have the issuer's name!
                        if is_internal "$b64_issuer"; then
                        CAList+="$currentcertname"$'\n'
                    fi
                    else
                        # If we couln't get the issuer's name, let skip this check and carry on...
                        return 0
                    fi
                fi
            fi
        fi
    done <<< "$output"

    # Removing duplicate from the signing Root CA certificates list
    CAList=$(echo $CAList | sort | uniq) 

    # We want to see the summary
    CAList=$(echo "$CAList" | grep -v '^\s*$') # Remove empty lines...
    if [[ -n "${quiet}" && -z "${silent-}" ]]; then unquiet; fi
    echo; logI "The below is a list of Internal CAs with the ability to sign other certificate:"
    logI "    These are most likely used to sign internal servers or to perform SSL Forward Inspection (MITM)\n"
    logonly "$CAList"; echo "$CAList"
}



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

###############################   RUNTIME   ################################

echo; logI "  ---   ${PINK}SCRIPT: $script_dir/$scriptname${NC}   ---"
logI "        ${PINK}     This script is intended to identify and extract a list of Internal signing Certificate Authorities...${NC}"

# If not invoked/sourced by another script, we'll set some variable for standalone use...
if [[ -z "${invoked-}" ]]; then 
    echo -e "Summary: The purpose of this script is to extract a list of internal signing certificate authorities form the Keychain Manager in MacOS"
    echo    "         It only retain Root and/or Intermediate signing CAs that are internal and it builds a list of it."
    echo -e "Author:  florian@photonsec.com.au\t\tgithub.com/Enelass\nRuntime: currently running as $(whoami)"
    echo "This script was invoked directly... Setting variable for standalone use..."
fi

keychainCA
if [[ -n "${silent-}" ]]; then unquiet; fi