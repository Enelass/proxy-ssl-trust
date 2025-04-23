#!/bin/zsh
# Author: Florian Bidabe
# Date of Release: 14-Mar-2025
# Description: This script manages and updates certificate stores on macOS systems by adding internal Root CAs
# from the OS Keychain Manager to specified PEM certificate stores. It ensures that only new or updated certificates
# are added, maintaining a backup of the original PEM files for restoration if needed.
# This script is designed to be part of a larger system for managing certificate stores on macOS. It relies on other scripts and files to function correctly. Ensure all dependencies are in place and correctly configured before running this script.
# The script adds the Base64 Root           #
#               certificate authorities to the various client certificate store    #
#               conventionally named (cacert.pem)

local scriptname=$(basename $(realpath $0))
local current_dir=$(dirname $(realpath $0))

# Condition to verify is teefile (the log file) is defined. If not, this script wasn't sourced/called/invoked by the main, so we'll abort
if [[ -z "${BLUEW-}" ]]; then 
    echo -e "WARNING - This script is not meant to be executed directly!\nIt will only run if invoked/sourced from proxy_cert_auto_setup.sh"
    exit 1
fi

# Function to uninstall the files created by --scan and remove all files altered by patch + restore the .original file
uninstall(){
	open "$teefile"
	if [[ ! -f "$cacertdb" ]]; then
		log "Error   - Cannot find $cacertdb... If we do not have a list of patched patchted PEM file, we cannot revert the changes...\n\t\t\tPlease run this script again with the --scan switch or no switches to force a new scan"
		exit 1
	fi
	log "Info    -    Requesting uninstallation"
	counter=0
	while IFS= read -r line; do
	    if [ $counter -gt 0 ]; then
	        pem_path=$(echo "$line" | cut -d',' -f2)
	        shortened_string=$(truncate_string "$pem_path")
	        pem_dir=$(dirname "$pem_path")
	        if [[ -d "$pem_dir" ]] && find "$pem_dir" -type f \( -name '*.original' -o -name '*.bak' \) ; then
					  log "Info - Restoring to vanilla files for $shortened_string..."
					  logonly "Files found and to be deleted: $(find . -type f \( -name '*.original' -o -name '*.bak' \) | xargs)"
					  # Delete the bak
					  # if original, force replace <name.pem.original> <name.pem> even if a file with the same name exists (overwritte)
					else
					  logonly "Info - Could find .bak files and/or .original for $shortened_string"
					  logonly "Info -    This wasn't patched (e.g. Exclude flag) or a clean-up was already run"
					fi
	        sleep 3
	    fi
	    counter=$((counter + 1))
	done < "$cacertdb"


	# Delete scan docs in $CDir

}

truncate_string() {
  local input="$1"
  local max_length=100
  local middle="..."
  local middle_length=${#middle}

  if (( ${#input} > max_length )); then
    local part_length=$(( (max_length - middle_length) / 2 ))
    local front_part back_part
    front_part=${input[1,part_length]}
    back_part=${input[-part_length,-1]}
    echo "${front_part}${middle}${back_part}"
  else
    echo "$input"
  fi
}

# Function to add the internal Root CAs from the OS Keychain Manager to the certificate stores (cacert.pem) found during the scan
trustca() {
	cacert="$1"		# $1 is the pem files to be patched... where $2 is the name of the application requiring it
	if [ ! -f "$cacert" ]; then
	  log "Error    -    Certificate Store for "$2" could not be located at $cacert... It will not be patched. Error was reported in the logfile"
	else
	  log "Info    -     Certificate Store for "$2" is being processed..."
	  # Also make a one time only backup, if the pem file is the original / shipped pem file (for the purpose of restoring/uninstall proxy_cert_auto_setup) 
	  if [[ ! -f $cacert.original ]]; then cp $cacert $cacert.original; fi

	  # Adds .bak extension to back it up the pem file everytime we patch it...
	  cacertbackup=$cacert.$(date '+%F_%H%M%S').bak
	  cp $cacert $cacertbackup	# Make a(n) (extra) backup

	  # If we have more than five dated backup, erase the oldest (we don't want a evergrowing list of backup files)
	  cd "$(dirname $cacert)"
	  ls -t $(basename $cacert).*.bak | tail -n +5 | xargs rm 
	  

	  # Iterate through all custom certificate in the Keychain (excluding System Roots / Public RootCA by default)
	  while read -r line; do # Use cut to extract the base 64 CA certifacte from the line
	    certname=$(echo $line | cut -d\" -f2) # Extract cert names
	    b64cert=$(security find-certificate -c $certname -p) # Find the matched cert
	    line4=$(echo $b64cert | awk 'NR==4{print $0}') # Extract third line of cert for pattern matching (line 4 of whole cert, low risk of crypto collision)
	    if ! grep -q $line4 $cacert; then 
	      echo -e "\n# Internal Signing Root CA: $certname" >> $cacert
	      echo $b64cert >> $cacert # If line4 isn't found in cert then append it to cacert.pem
	        if [ $? -ne 0 ]; then # Error function to abort if copying is unsuccessful
	          log "Error   -         Something went wrong when trying to copy $certname into $cacert!"
	          log "Info    -         Restoring Original cacert.pem file..."
	          cp $cacertbackup $cacert # Error function to abort if copying backup of cert is unsuccessful
	          if [ $? -ne 0 ]; then handle_error "Error   - Restore Unsuccessfull. Aborting!"; fi
	          exit 1
	        fi
	        echo "$(timestamp) Success -           $certname is now trusted in this certificate store for $2" >> $teefile
	    else
	    	echo "$(timestamp) Info    -           $certname was already trusted in this certificate store for $2" >> $teefile
	    fi   
	  done <<< "$IntCAList"
	  log "Success -     $2 Certificate Store now trusts our internal CAs"
	fi
}


######################################################################### Execution #########################################################################


###########################   Script SWITCHES   ###########################
# Switches and Executions for the initial call (regardless of when)
while [[ $# -gt 0 ]]; do
  case $1 in
    --uninstall|-u) uninstall ;;
   *) ;;
  esac
  shift
done

echo; logI "  ---   ${PINK}SCRIPT: $current_dir/$scriptname${NC}   ---"
logI "        ${PINK}     This script is intended to patch a supplied (by --scan or PEM_Scan.sh) list of PEM Certificate Stores...${NC}"

# We need both a list of MacOS internal Root CAs (see command below) to add to each PEM certificate store we have (cacertdb IF statement below as well)
source "$current_dir/Keychain_InternalCAs.sh" --silent		# This command will invoke the script with variable $IntCAList which list the names of Internal Signing Root CAs

log "Info    -     We will now patch the PEM certificate store we know about..."
	if [[ ! -f "$cacertdb" ]]; then
		log "Error   - Cannot find a list of certificate store (PEM files) to scan at $cacertdb...\n\t\t\t      Please run this script again with the --scan switch or no switches to force a new scan"
	else
		log "Info    - Time to process each PEM certificate store one by one..."
		counter=0 # Need to skip the first line since it's the CSV header...
		while IFS= read -r line; do
			if [ $counter -gt 0 ]; then
			    application_name=$(echo "$line" | cut -d',' -f1)
			    pem_path=$(echo "$line" | cut -d',' -f2)			# This is the full path for any verified PEM certificate store
			    magic_byte=$(echo "$line" | cut -d',' -f3)
			    sha1=$(echo "$line" | cut -d',' -f4)
			    timestamp=$(echo "$line" | cut -d',' -f7)
			    exclude=$(echo "$line" | cut -d',' -f8)
			    logonly "Info    -   Processing PEM certificate store found at "$pem_path""
			    shortened_string=$(truncate_string "$pem_path")
			    log "Info    -   Processing PEM certificate store number: $counter"
			    log "Info    -     Inspecting "$shortened_string""
			    if [ "$exclude" -eq 1 ]; then
            log "Info    -     This certificate is marked for exclusion... skipping!"
            log "Info    -     If you wish to patch it, change the Exlude flag from 1 to 0 in "$cacertdb""
            counter=$((counter + 1)); continue
		      fi
			    if [[ -f "$previousdb" ]]; then  # Does a previous Db exist? If so we'll run further checks to patch only what hasn't been patched already...
				    if grep -q "$pem_path" "$previousdb"; then # Did the previous Db have this cacert.pem path?
				        previous_sha1=$(grep "$pem_path" "$previousdb" | awk -F',' '{print $4}')
				        if [[ "$sha1" == "$previous_sha1" ]]; then	# If it did have that cacert.pem path, was the sha1 signature the same?
				            #echo "Current SHA is: $sha1, Previous was: $previous_sha1"
				            log "Info    -    This entry exist and was patched already... skipping!"
				        else
				            log "Info    -    Current SHA is: $sha1, Previous was: $previous_sha1"
				            log "Info    -    This entry is new, we will patch it..."
				            trustca "$pem_path" "$application_name"	# Path is SHA1 signatures are different, e.g. cacert.pem was updated and needs to be patched again
				        fi
				    fi
					else # There is no old db, so let's patch it all (every PEM Certificate store we have found)!
						trustca "$pem_path" "$application_name"
					fi
			fi
			counter=$((counter + 1))
		done < "$cacertdb"
	fi