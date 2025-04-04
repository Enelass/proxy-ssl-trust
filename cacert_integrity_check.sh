#!/bin/zsh
script_name="$0"
script_dir=$(dirname $(realpath $0))
pem_error=false

# If this is a standalone execution...
if [[ -z "${teefile-}" ]]; then 
    AppName="pem_integrity_check"
    teefile="/tmp/$AppName.log"
fi

if [[ -z "${logI+x}" || -z "${logI}" ]]; then 
    source "$script_dir/stderr_stdout_syntax.sh"
fi

# Help function
help() {
  echo -e "Usage: $0 [options] [pem_file_path]
Options:
    --help, -h       Show this help message and exit.
    --quiet, -q      Suppress the output except for errors.
Description:
    This script checks the integrity of PEM files containing certificates by parsing them and validating each certificate using OpenSSL.
    It reads the provided PEM file, lists the certificates, and verifies each one. If any certificate is invalid, it logs an error.
    The script displays a progress bar as it processes the certificates.
    If no PEM file path is specified as an argument, the script prompts the user to input the path interactively.
Example Usage:
    $script_name --path /path/to/certificate.pem     # Validates certificates in the specified PEM file.
    $script_name -q -p /path/to/certificate.pem # Validates certificates quietly and saves status in pem_error variable
    $script_name                              # Prompts for PEM file path interactively.
Author:
    florian@photonsec.com.au
    github.com/Enelass"
    exit 0
}

# Function to display a progress bar
show_progress_bar() {
  local current=$1
  local total=$2
  local bar_length=50
  local progress=$((current * bar_length / total))
  local remainder=$((bar_length - progress))
  printf "\r["
  printf "%${progress}s" | tr " " "="
  printf "%${remainder}s] " " "
  printf " %d/%d" "$current" "$total"
}

# Function to check the integrity of pem file and its embedded certificates
pem_integrity_check(){
  local pem_file=$1
  local cert_count=0
  local current_cert_index=0

  # Read entire pem file content
  content=$(<"$pem_file")

  # Initialize array and temporary variable to store current certificate
  certs=()
  current_cert=""
	current_cert_index=1
  # Scan through each line of the file and construct certificates
  while IFS= read -r line; do
    current_cert+="$line"$'\n'
    if [[ "$line" == "-----END CERTIFICATE-----" ]]; then
      certs+=("$current_cert")
      current_cert=""
      cert_count=$((cert_count + 1))
    fi
  done <<< "$content"

  logI "Processing certificates in $pem_file. Please wait..."
  logI "There are ${BLUEW}${cert_count} certificates${NC} in this certificate store"

  # Iterate over each certificate in the array and inspect it using OpenSSL
  for cert in "${certs[@]}"; do
    # Verification of the certificate
    echo "$cert" | openssl x509 -text -noout >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      pem_error=true
      logonly "Certificate number $current_cert_index is not valid..."
      cert_error+="$current_cert_index) $(echo "$cert" | sed -n 's/.*CN=\([^,\/]*\).*/\1/p' | sort -u)   "
    fi
    show_progress_bar $current_cert_index $cert_count
    current_cert_index=$((current_cert_index + 1))
  done
  echo
}

###########################   Script SWITCHES   ###########################
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --quiet|-q)
            shift
            if [[ -z $1 ]]; then
                logE "Quiet mode requires a path... e.g. $0 --quiet --path /private/etc/ssl/cert.pem"
                exit 1
            fi
            quiet
            ;;
        --help|-h) clear ; help ;;
        --path|-p)
            pem_file="$2"
            shift 2
            ;;
        -*|--*)
            clear
            logW "Invalid switch ${GREENW}$1${NC}. Refer to the usage instructions below."
            help
            ;;
        *) clear; logE "Invalid input. Refer to the usage instructions"; help ;;
    esac
done

###############################   RUNTIME   ################################
# If not invoked/sourced by another script, we'll set some variables for standalone use...
if [[ -z "${invoked-}" ]]; then
    clear
    echo "$1 $2 $3 pem_file $pem_file"
    echo -e "Summary: This script checks the integrity of PEM files containing certificates by parsing them and validating each certificate using OpenSSL.
         It reads the PEM file, lists the certificates, and verifies each one. If any certificate is invalid, it logs an error. The script shows a
         progress bar as it processes the certificates. Additionally, it provides an option to input the PEM file path if not specified."
    echo -e "Author:  florian@photonsec.com.au\t\tgithub.com/Enelass\nRuntime: currently running as $(whoami)\n"
    logonly "This script was executed directly and not sourced from another script..."
fi

if [[ -z ${pem_file-} ]]; then
    logI "Please input our certificate store (pem file) full path:"
    read "pem_file"
fi

if [[ ! -f "$pem_file" ]]; then
    logE "File $pem_file not found!"
    exit 1
fi

cert_count1=$(grep -c -- '-----BEGIN CERTIFICATE-----' "$pem_file")
cert_count2=$(grep -c -- '-----END CERTIFICATE-----' "$pem_file")

if [[ $cert_count1 -eq 0 ]]; then
    pem_error=true
    logE "There are no Base64 certificates in this file."
    exit 1
fi

if [[ $cert_count1 -ne $cert_count2 ]]; then
    pem_error=true
    logW "Certificate boundaries are not set properly."
fi

echo "Do we get there?"

# Time to process that good-looking pem file...
pem_integrity_check "$pem_file"



if [[ "$pem_error" == "true" ]]; then
    logW "This pem file is corrupted or contains corrupted Base 64 entries (certificates)"
    logW "Erroneous certificate numbers: $cert_error"
    return 1
else
    logS "No issue within this Certificate Store"; return 0
fi

if [[ -n "${silent-}" || -n "${quiet-}" ]]; then
    unquiet
fi