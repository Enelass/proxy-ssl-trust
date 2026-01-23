#!/bin/zsh

#################### Written by Florian Bidabe #####################################
#                                                                                  #
#  DESCRIPTION: The purpose of this script is to provide various CLI on MacOS with #
#                a custom PEM certificate store including public and internal Root #
#                certificate authorities. This will resolve number of connectivity #
#                issues where CLI not relying on the MacOS Keychain Access can     #
#                still trust internally signed servers using an Internal Root CA   #
#                and trust https connections where SSL forward inspection is       #
#                performed and signed on a fly by a proxy/ngfw internal CA.        #
#  INITIAL RELEASE DATE: 19-Mar-2025                                               #
#  AUTHOR: Florian Bidabe                                                          #
#  LAST RELEASE DATE: 19-Mar-2025                                                  #
#  VERSION: 0.1                                                                    #
#  REVISION:                                                                       #
#                                                                                  #
#                                                                                  #
####################################################################################
version=0.2
cacertURL="https://curl.se/ca/cacert.pem"
local scriptname=$(basename $(realpath $0))
local current_dir=$(dirname $(realpath $0))
variables=("REQUESTS_CA_BUNDLE" "SSL_CERT_FILE")
extravarfile="$current_dir/ssl_vars.config"

# If not invoked/sourced by another script, we'll set some variable for standalone use otherwise this would be ineritated by the source script along with $teefile...
if [[ -z ${BLUEW-} ]]; then source "$current_dir/../lib/stderr_stdout_syntax.sh"; fi
if [[ -z "${invoked-}" ]]; then 
    echo -e "\n\nSummary: The purpose of this script is to provide various CLI on MacOS with environment variables referencing a custom PEM certificate store including public and internal Root
         certificate authorities. This will resolve number of connectivity issues where CLI not relying on the MacOS Keychain Access can still trust internally
         signed servers using an Internal Root CA and trust https connections where SSL forward inspection is performed and signed on a fly by a proxy/ngfw internal CA."
    echo -e "Author:  contact@photonsec.com.au\t\tgithub.com/Enelass\nRuntime: currently running as $(whoami)"
    echo "This script was invoked directly... Setting variable for standalone use..."
    
    #################################   Variables     ####################################
    AppName="PEM_EnvVar"
    teefile="/tmp/$AppName.log"
    version=0.2
    ######################################################################################
fi


# Function to display the Help Menu
help() {
    clear
    echo -e "Summary: The purpose of this script is to provide various CLI on MacOS with environment variables referencing a custom PEM certificate store including public and internal Root
         certificate authorities. This will resolve number of connectivity issues where CLI not relying on the MacOS Keychain Access can still trust internally
         signed servers using an Internal Root CA and trust https connections where SSL forward inspection is performed and signed on a fly by a proxy/ngfw internal CA."
    echo -e "Author:  contact@photonsec.com.au\t\tgithub.com/Enelass\nRuntime: currently running as $(whoami)\nVervion: $version\n"
    echo -e "Usage: $@ [OPTION]..."
    echo -e "  --help, -h\tDisplay this help menu..."
    echo -e "  --uninstall\tRemove the environement variables from Shell config file and remove downloaded files and backups"
    echo -e "  By default, if no switches are specified, it will run standone with verbose information"
    exit 0
}

# Function to check if we're running on MacOS
get_macos_version() { local product_name=$(sw_vers -productName); local product_version=$(sw_vers -productVersion); local build_version=$(sw_vers -buildVersion); echo "$product_name $product_version ($build_version)" }


extravar(){
	if [[ -f "$extravarfile" ]]; then 
		# Read variables from ssl_vars.config, ignoring comments and stripping quotes
		while IFS= read -r line; do
		  [[ $line =~ ^# ]] && continue
		  [[ $line =~ ^\"(.+)\"$ ]] && line="${match[1]}"
		  
		  # Regex to allow only uppercase letters, numbers, underscores, and dashes
		  if [[ -n $line && $line =~ ^[A-Z0-9_-]+$ ]]; then
		    variables+=("$line")
		  fi
		done < "$extravarfile"

		# Remove duplicates and sort
		variables=($(printf "%s\n" "${variables[@]}" | sort -u))
	fi
}

uninstall(){
	if [[ -z ${overwrite-} ]]; then logI "    Requesting uninstallation" ; fi
	source "$current_dir/../lib/user_config.sh"
	pattern='.config\/cacert\/cacert.pem'
	for var in "${variables[@]}"; do unset "$var"; done # Loop through the array and unset custom Certificate Store variable for various clients
	if [[ -f "$CONFIG_FILE" ]]; then 
		 sed -i '' "/"$pattern"/d" "$CONFIG_FILE"
		 if [[ $? -ne 0 ]]; then
		 	logE " Parsing the Shell Config file failed... aborting!"
		 else 
		 	logI "    Entries in the Shell config file at $CONFIG_FILE were cleaned-up..."
		 	source $CONFIG_FILE		# Reload Shell config file to make the changes (restore) effective
		 fi
	else
		logE "    Shell config file wasn't found..."
	fi
	
	if [[ -d $HOME_DIR/.config/cacert/ ]]; then
		rm -Rf "$HOME_DIR/.config/cacert/" 2>/dev/null
		if [[ $? -eq 0 ]]; then log "Info    -    Files downloaded by this script were cleaned-up..."; fi
	else logE " $HOME_DIR/.config/cacert/ could not be found! You probably already have requested an uninstallation..."
	fi
	if [[ -z ${overwrite-} ]]; then exit 0 ; fi
}

# Function to add the internal Root CAs from the OS Keychain Manager to the certificate stores (cacert.pem)
trustca() {
	cacert="$1"		# $1 is the pem files to be patched... where $2 is the name of the application requiring it
	if [ ! -f "$cacert" ]; then
	  logW "    Custom Certificate Store could not be located at "$cacert"..."
	  logE "    It will not be patched. Error was reported in the logfile"
	else
	  logI "    It will be patched with Internal Root CAs from the MacOS Keychain Access:"
	  # Adds .bak extension to back it up the pem file everytime we patch it...
	  cacertbackup=$cacert.$(date '+%F_%H%M%S').bak
	  cp $cacert $cacertbackup	# Make a(n) (extra) backup
	  # If we have more than five dated backup, erase the oldest (we don't want a evergrowing list of backup files)
	  cd "$(dirname $cacert)"
	  ls -t $(basename $cacert).*.bak | tail -n +5 | xargs rm 
	  

	  # Go through each internal Root signing CA in Keychain Access one at a time to add the certificate or skip it
	  # (skip if duplicates are found, since the certificate was already added)
	  while read -r line; do # Use cut to extract the base 64 CA certifacte from the line
	    certname=$(echo $line | cut -d\" -f2) # Extract cert names
	    b64cert=$(security find-certificate -c $certname -p) # Find the matched cert
	    line4=$(echo $b64cert | awk 'NR==4{print $0}') # Extract third line of cert for pattern matching (line 4 of whole cert, low risk of crypto collision)
	    if ! grep -q $line4 $cacert; then 
	      echo -e "\n# Internal Signing Root CA: $certname" >> $cacert
	      echo $b64cert >> $cacert # If line4 isn't found in cert then append it to cacert.pem
	        if [ $? -ne 0 ]; then # Error function to abort if copying is unsuccessful
	          logW "         Something went wrong when trying to copy $certname into $cacert!"
	          logI "         Restoring Original cacert.pem file..."
	          cp $cacertbackup $cacert # Error function to abort if copying backup of cert is unsuccessful
	          if [ $? -ne 0 ]; then logE " Restore Unsuccessfull. Aborting!"; fi
	          exit 1
	        fi
	       logS "       ${BLUEW}$certname${NC} is now trusted in our custom certificate store"
	    else logI "       ${BLUEW}$certname${NC} was already trusted in our custom certificate store"
	    fi
	  done <<< "$CAList"
	  log "Success - Custom Certificate Store now includes our internal Root CAs"
	fi
}

shell_var(){
	log "Info    -    Looking for CA related Environment Variables in Shell Config $CONFIG_FILE"
	# Function to check if a file contains a specific variable
	contains_variable() {
	  local variable=$1
	  if grep -q "^export $variable=" "$CONFIG_FILE"; then
	    logW "      ${GREENW}$variable${NC} was already set in in the user's Shell Config file"
	    logI "          $(cat "$CONFIG_FILE" | grep "$variable")"
	    logI "          If this entry is incorrect, please correct it manually with a text editor..."
	  else
	    if [[ -z ${overwrite-} ]]; then logI "      Adding ${GREENW}$variable${NC} was not set in $CONFIG_FILE. Let's add it..." ; fi
 		echo "export "$variable"=\""$customcacert"\"" >> $CONFIG_FILE
 		# Check again, if we were able to add the variable
 		if grep -q "^export $variable=" "$CONFIG_FILE"; then
		    logS "         export ${GREENW}$variable${NC}=\""$customcacert"\" has been added to the Shell config file..." 
	    else
	    	logE "         $variable could not be added to $CONFIG_FILE! Aborting..."
	    fi
	  fi
	}

	# Iterate over each variable and check
	for var in "${variables[@]}"; do
	  contains_variable "$var"
	done
}

# Download the latest cacert.pem from curl.se (It contains an updated list of Public Root CAs)
cacert_download() {
	if [[ -z ${HOME_DIR-} ]]; then source "$current_dir/../lib/user_config.sh"; fi
	customcacert="$HOME_DIR/.config/cacert/cacert.pem"
	logI " Downloading and/or locating custom PEM certificate" 
	# Create the directory for storing cacert.pem unless existing
	if [[ -d "$HOME_DIR/.config/cacert/" ]]; then
	else
		mkdir -p "$HOME_DIR/.config/cacert/"
	fi

	# check if cacert.pem already exists...
	if [[ -f "$customcacert" ]]; then
		logW "    Custom PEM certificate exists already. It will not be retrieved from the internet..."
	else
		cd $(dirname "$customcacert")
		for i in {1..3}; do curl -k -L -O "$cacertURL" >/dev/null 2>&1 && break || logW "    Download failed on attempt $i"; done	
		if [[ ! -f "$customcacert" ]]; then
			logW "    Something went wrong with downloading cacert.pem from "$cacertURL"..."
			logE "    Please troubleshoot the issue or contact support. Aborting!"
		fi
	fi
	logI "    Custom PEM certificate can be found at "$customcacert""
	 # We keep a vanilla cacert.pem as we'll use it to determine if a website isn't signed by a public CA
	 if [[ ! -f $customcacert.public ]]; then cp -f $customcacert "$customcacert.public"; fi
}

###########################   Script Switches and Runtime   ###########################

extravar # Executing the function to find all Shell variables to set (or unset for that matter)


# Switches and Executions for the initial call (regardless of when)
while [[ $# -gt 0 ]]; do
  case $1 in
    --help|-h) help ;;								
    --uninstall|-u) uninstall ;;					# Wipe everything this script did: custom certificate store (cacert.pem) and restore original ~/.zshrc (pre-reuntime of this script)
	--download|-d) cacert_download ;;				# It will download and build a custom certificate store (cacert.pem), but won't touch the Env variables in user's Shell Config 
	--daemon|-D) daemon ;;							# It will create a LaunchAgent in User Directory to periodically update the Custom Certificate so it remains up to date...
	--overwrite|-o) overwrite=true ; uninstall ;;	# It will force rewrite the cacert.pem + Env variables in user's Shell Config 
   *) ;;
  esac
  shift
done


# Execute the function to check web connectivity without SSL verification
echo; logI "  ---   ${PINK}SCRIPT: $current_dir/$scriptname${NC}   ---"
logI "        ${PINK}     This script will download a public Certificate Store and add Internal CAs to it${NC}"
logI "        ${PINK}     It will then create environment variable in the user shell config and reference it...${NC}"


source "$current_dir/../lib/user_config.sh" --quiet	# Let's identify the logged-in user, it's home directory, it's default Shell interpreter and associated config file...
cacert_download	# Let's download cacert.pem 

# Check if the certificate authority file is valid
source "$current_dir/PEM_Check.sh" --cafile "$customcacert"

# List the Internal Root CAs and patch cacert.pem with internal Root CAs
source "$current_dir/Keychain_InternalCAs.sh" --silent		# This command will invoke the script and return variable $CAList which lists the names of Internal Signing Root CAs from the Keychain Access in MacOS
trustca "$customcacert"

# Let's inspect the file for existing environement variables & Let's reference this cacert.pem in the Shell Interpreter config file
shell_var

source "$CONFIG_FILE"
cd "$script_dir"