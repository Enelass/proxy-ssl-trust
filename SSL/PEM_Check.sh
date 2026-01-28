#!/bin/zsh
local scriptname=$(basename $(realpath $0))
local current_dir=$(dirname $(realpath $0))
local pem_error

if [[ -z "${BLUEW-}" ]]; then
    source "$current_dir/../lib/stderr_stdout_syntax.sh"
    AppName="Pem_Integrity_Check"
    teefile="/tmp/$AppName.log"
fi

# Help function
help() {
  echo -e "Usage: $0 [options]
Options:
    --help, -h           Show this help message and exit.
    --quiet, -q          Suppress the output except for error status.
    --verbose, -v        Shows the verbose for each certificate subject and name
    --cafile, -c, -f     Path to the PEM file to inspect
 Description:
    This script checks the integrity of PEM files containing certificates by parsing them and validating each certificate using OpenSSL.
    It reads the provided PEM file, lists the certificates, and verifies each one. If any certificate is invalid, it logs an error.
    The script displays a progress bar as it processes the certificates.
    If no PEM file path is specified as an argument, the script prompts the user to input the path interactively.
 Example Usage:
    $scriptname --cafile /path/to/certificate.pem   # Validates certificates in the specified PEM file.
    $scriptname --verbose --cafile /path/to/crt.pem # Validates and displays certificate subjects from the specified PEM file
    $scriptname -q -f /path/to/certificate.pem      # Validates certificates quietly and saves status in pem_error variable
    $scriptname /path/to/certificate.pem            # Uses positional PEM path.
    $scriptname                                     # Prompts for PEM file path interactively.
 Author:
    contact@photonsec.com.au
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

# Function to detect and remove duplicate PEM certificate blocks in-place
dedupe_pem_file(){
  local pem_file=$1
  local tmp_file="${pem_file}.dedup.$$"
  local -A seen_hashes=()
  local -a pre_block=()
  local -a current_block=()
  local current_pem=""
  local in_pem=0
  local after_end=0
  local line pem_hash duplicate_subject
  local cert_index=0

  duplicate_certs=""

  exec 3>"$tmp_file" || {
    logE "Unable to create temporary file for deduplication: $tmp_file"
    return 1
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    # If we just finished a PEM block, decide whether to include a trailing blank line
    if (( after_end )); then
      if [[ -z "$line" ]]; then
        current_block+=("$line")
        # finalize block with trailing blank
      else
        # finalize block without consuming this non-blank line
        # (fall through to normal processing for this line)
      fi

      if (( ${#current_block[@]} > 0 )); then
        pem_hash=$(printf '%s' "$current_pem" | openssl dgst -sha256 2>/dev/null | sed 's/^.*= //')
        cert_index=$((cert_index + 1))
        if [[ -n "$pem_hash" && -n ${seen_hashes[$pem_hash]-} ]]; then
          duplicate_subject=$(printf '%s' "$current_pem" | openssl x509 -noout -subject 2>/dev/null | sed 's/^subject= *//')
          duplicate_certs+="$cert_index (same as ${seen_hashes[$pem_hash]}) [$duplicate_subject]  "
          logW "Removing duplicate certificate block #$cert_index (Subject: $duplicate_subject), duplicate of #${seen_hashes[$pem_hash]}"
          # Do not write this block to output
        else
          seen_hashes[$pem_hash]=$cert_index
          for l in "${current_block[@]}"; do
            print -u3 -- "$l"
          done
        fi
        current_block=()
        current_pem=""
      fi
      after_end=0
      # If we consumed the trailing blank line, continue to next line
      if [[ -z "$line" ]]; then
        continue
      fi
      # Otherwise fall through to process this non-blank line
    fi

    # Inside a PEM certificate block
    if (( in_pem )); then
      current_block+=("$line")
      current_pem+="$line"$'\n'
      if [[ "$line" == *"-----END CERTIFICATE-----"* ]]; then
        in_pem=0
        after_end=1
      fi
      continue
    fi

    # Not currently in a PEM block
    if [[ "$line" == *"-----BEGIN CERTIFICATE-----"* ]]; then
      current_block=()
      # Attach any comment block immediately above
      if (( ${#pre_block[@]} > 0 )); then
        for l in "${pre_block[@]}"; do
          current_block+=("$l")
        done
        pre_block=()
      fi
      current_block+=("$line")
      current_pem="$line"$'\n'
      in_pem=1
      continue
    fi

    # Handle blank lines outside PEM blocks
    if [[ -z "$line" ]]; then
      # A blank line breaks any pending comment block; flush comments then the blank
      if (( ${#pre_block[@]} > 0 )); then
        for l in "${pre_block[@]}"; do
          print -u3 -- "$l"
        done
        pre_block=()
      fi
      print -u3 -- "$line"
      continue
    fi

    # Handle comment lines that may belong to the next certificate
    if [[ "$line" == \#* ]]; then
      pre_block+=("$line")
      continue
    fi

    # Any other non-comment, non-blank line: flush pending comments and write the line
    if (( ${#pre_block[@]} > 0 )); then
      for l in "${pre_block[@]}"; do
        print -u3 -- "$l"
      done
      pre_block=()
    fi
    print -u3 -- "$line"
  done <"$pem_file"

  # Finalize a PEM block if file ended right after it
  if (( after_end )) && (( ${#current_block[@]} > 0 )); then
    pem_hash=$(printf '%s' "$current_pem" | openssl dgst -sha256 2>/dev/null | sed 's/^.*= //')
    cert_index=$((cert_index + 1))
    if [[ -n "$pem_hash" && -n ${seen_hashes[$pem_hash]-} ]]; then
      duplicate_subject=$(printf '%s' "$current_pem" | openssl x509 -noout -subject 2>/dev/null | sed 's/^subject= *//')
      duplicate_certs+="$cert_index (same as ${seen_hashes[$pem_hash]}) [$duplicate_subject]  "
      logW "Removing duplicate certificate block #$cert_index (Subject: $duplicate_subject), duplicate of #${seen_hashes[$pem_hash]}"
      # Do not write this block
    else
      seen_hashes[$pem_hash]=$cert_index
      for l in "${current_block[@]}"; do
        print -u3 -- "$l"
      done
    fi
  fi

  # Flush any remaining comment block at end of file
  if (( ${#pre_block[@]} > 0 )); then
    for l in "${pre_block[@]}"; do
      print -u3 -- "$l"
    done
  fi

  exec 3>&-

  mv "$tmp_file" "$pem_file" || {
    logE "Failed to replace original PEM file with deduplicated version."
    return 1
  }

  if [[ -n ${duplicate_certs-} ]]; then
    logI "Removed duplicate certificate blocks from PEM file."
  fi
}

# Function to check the integrity of pem file and its embedded certificates
pem_integrity_check(){
  local pem_file=$1
  local cert_count=0
  local current_cert_index=0
  local content current_cert=""
  local -a certs=()
  local certCN
  local openssl_status
  cert_CNs=""

  # Read entire pem file content
  content=$(<"$pem_file")

  # Initialize array and temporary variable to store current certificate
  current_cert_index=1
  # Scan through each line of the file and construct certificates
  while IFS= read -r line; do
    current_cert+="$line"$'\n'
    if [[ "$line" == *"-----END CERTIFICATE-----"* ]]; then
      certs+=("$current_cert")
      current_cert=""
      cert_count=$((cert_count + 1))
    fi
  done <<< "$content"

  logI "Processing certificates in \"$pem_file\". Please wait..."
  logI "There are ${BLUEW}${cert_count} certificates${NC} in this certificate store"

  # Iterate over each certificate in the array and inspect it using OpenSSL
  local idx=1
  while (( idx <= cert_count )) && can_continue; do
    local cert="${certs[idx]}"
    current_cert_index=$idx

    # Check for interrupt before processing this certificate
    check_interrupted

    # Verification of the certificate

    if [[ ${verbose:-0} -eq 1 ]]; then
        certCN=$(
          echo "$cert" | openssl x509 -text -noout 2>/dev/null \
            | sed -n 's/.*CN=\([^,\/]*\).*/\1/p' \
            | sort -u \
            | xargs
        )
        openssl_status=$?
        if [[ -z "$certCN" ]]; then
          certCN=$(
            echo "$cert" | openssl x509 -text -noout 2>/dev/null \
              | grep "Subject: "
          )
          openssl_status=$?
        fi
    else
        echo "$cert" | openssl x509 -text -noout >/dev/null 2>&1
        openssl_status=$?
    fi

    if [[ $openssl_status -ne 0 ]]; then
      pem_error=true
      echo
      logonly "Certificate number $current_cert_index is not valid..."
      cert_error+="$current_cert_index) $certCN   "
    fi
    # echo "$current_cert_index )   $certCN"
    if [[ ${verbose:-0} -eq 1 ]]; then
        cert_CNs+="$current_cert_index) $certCN\n"
    fi
    
    # Check for interrupt before showing progress bar
    check_interrupted
    show_progress_bar $current_cert_index $cert_count
    current_cert_index=$((current_cert_index + 1))
    idx=$((idx + 1))
  done
  echo -en "\r\033[2K\033[F\033[2K";  # Clear the previous line
}

###########################   Script SWITCHES   ###########################
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --verbose|-v)
            verbose=1
            shift
            ;;
        --quiet|-q)
            if [[ ${verbose:-0} -eq 1 ]]; then
                logE "Quiet cannot be verbose..."
                if [[ -n ${invoked-} ]]; then
                    return 1
                else
                    exit 1
                fi
            fi
            quiet
            shift
            ;;
        --help|-h) clear ; help ;;
        --cafile|-c|-f)
            pem_file="$2"
            shift 2
            ;;
        -*|--*)
            clear
            logW "Invalid switch ${GREENW}$1${NC}. Refer to the usage instructions below."
            help
            ;;
        *)
            if [[ -z ${pem_file-} ]]; then
                pem_file="$1"
                shift
            else
                clear
                logE "Invalid input. Refer to the usage instructions"
                help
            fi
            ;;
    esac
done

###############################   RUNTIME   ################################
if [[ -z "${invoked-}" ]]; then clear; fi
echo; logI "  ---   ${PINK}SCRIPT: $current_dir/$scriptname${NC}   ---"
logI "        ${PINK}     The purpose of this script is to scan a PEM Certificate Store to ensure its integrity...${NC}"

# If not invoked/sourced by another script, we'll set some variables for standalone use...
if [[ -z "${invoked-}" ]]; then
    echo -e "Summary: This script checks the integrity of PEM files containing certificates by parsing them and validating each certificate using OpenSSL.
         It reads the PEM file, lists the certificates, and verifies each one. If any certificate is invalid, it logs an error. The script shows a
         progress bar as it processes the certificates. Additionally, it provides an option to input the PEM file path if not specified."
    echo -e "Author:  contact@photonsec.com.au\t\tgithub.com/Enelass\n"
    logonly "This script was executed directly and not sourced from another script..."
fi

if [[ -z ${pem_file-} ]]; then
    logI "Please input our certificate store (pem file) full path:"
    read "pem_file"
fi

if [[ ! -f "$pem_file" ]]; then
    logE "File \"$pem_file\" not found!"
    if [[ -n ${invoked-} ]]; then
        return 1
    else
        exit 1
    fi
fi

cert_count1=$(grep -c -- '-----BEGIN CERTIFICATE-----' "$pem_file")
cert_count2=$(grep -c -- '-----END CERTIFICATE-----' "$pem_file")

if [[ $cert_count1 -eq 0 ]]; then
    pem_error=true
    logE "There are no Base64 certificates in this file."
    if [[ -n ${invoked-} ]]; then
        return 1
    else
        exit 1
    fi
fi

if [[ $cert_count1 -ne $cert_count2 ]]; then
    pem_error=true
    logW "Certificate boundaries are not set properly."
fi

# First, detect and remove duplicate certificate blocks from the PEM file
dedupe_pem_file "$pem_file"

# Time to process that good-looking pem file...
pem_integrity_check "$pem_file"

if [[ "${pem_error-}" == "true" ]]; then
    if [[ -n ${cert_error-} ]]; then
        logW "This pem file is corrupted or contains corrupted Base 64 entries (certificates)"
        logW "Erroneous certificate numbers: $cert_error"
    fi
    if [[ -n ${invoked-} ]]; then
        return 1
    else
        exit 1
    fi
else
    logS "No issue within this Certificate Store"
fi

if [[ ${verbose:-0} -eq 1 ]]; then echo -e "$cert_CNs"; fi
if [[ -n $silent || -n $quiet ]]; then unquiet; fi
