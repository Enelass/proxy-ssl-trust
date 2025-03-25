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
scriptpath=$(pwd)

# If not invoked/sourced by another script, we'll set some variable for standalone use otherwise this would be ineritated by the source script along with $teefile...
if [[ -z "${teefile-}" ]]; then 
    clear
    echo -e "Summary: The purpose of this script is to provide various CLI on MacOS with environment variables referencing a custom PEM certificate store including public and internal Root
         certificate authorities. This will resolve number of connectivity issues where CLI not relying on the MacOS Keychain Access can still trust internally
         signed servers using an Internal Root CA and trust https connections where SSL forward inspection is performed and signed on a fly by a proxy/ngfw internal CA."
    echo -e "Author:  florian@photonsec.com.au\t\tgithub.com/Enelass\nRuntime: currently running as $(whoami)"
    echo "This script was invoked directly... Setting variable for standalone use..."
    
    #################################   Variables     ####################################
    AppName="PEM_EnvVar"
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


# Function to display the Help Menu
help() {
    clear
    echo -e "Summary: The purpose of this script is to provide various CLI on MacOS with environment variables referencing a custom PEM certificate store including public and internal Root
         certificate authorities. This will resolve number of connectivity issues where CLI not relying on the MacOS Keychain Access can still trust internally
         signed servers using an Internal Root CA and trust https connections where SSL forward inspection is performed and signed on a fly by a proxy/ngfw internal CA."
    echo -e "Author:  florian@photonsec.com.au\t\tgithub.com/Enelass\nRuntime: currently running as $(whoami)\nVervion: $version\n"
    echo -e "Usage: $@ [OPTION]..."
    echo -e "  --help, -h\tDisplay this help menu..."
    echo -e "  --uninstall\tRemove the environement variables from Shell config file and remove downloaded files and backups"
    echo -e "  By default, if no switches are specified, it will run standone with verbose information"
    exit 0
}


uninstall(){
	log "Info    -    Requesting uninstallation"
	default_user; shell_config
	pattern='.config\/cacert\/cacert.pem'
	if [[ -f "$CONFIG_FILE" ]]; then 
		 sed -i '' "/"$pattern"/d" "$CONFIG_FILE"
		 if [[ $? -ne 0 ]]; then
		 	log "Error - Parsing the Shell Config file failed... aborting!"; exit 1
		 else log "Info    -    Entries in the Shell config file at $CONFIG_FILE were cleaned-up..."
		 fi
	else log "Error    -    Shell config file wasn't found..."; exit 1; fi
	if [[ -d $HOME_DIR/.config/cacert/ ]]; then
		rm -R "$HOME_DIR/.config/cacert/"
		if [[ $? -eq 0 ]]; then log "Info    -    Files downloaded by this script were cleaned-up..."; fi
	else log "Error - $HOME_DIR/.config/cacert/ could not be found..."; exit 1
	fi
	exit 0
}


# Function to identify the shell interpreter and its config file
shell_config() {
	log "Info    - Identifying the Shell interpreter" 
	DEFAULT_SHELL=$SHELL 									# Determine default shell
	CURRENT_SHELL=$(ps -p $$ -o comm=) 		# Determine current shell
	if [[ "$DEFAULT_SHELL" ==  "$CURRENT_SHELL" ]]; then
		log "Info    -    Default Shell: $DEFAULT_SHELL matches the current Shell: $CURRENT_SHELL"
	else
		log "Error   -    Default Shell: $DEFAULT_SHELL does not match the current Shell: $CURRENT_SHELL"
		log "Info    -    We'll abort, otherwise we'd set the environement variables in a Shell interpreters that isn't used by the user"; exit 1
	fi

	# Define config file based on the shell
	CONFIG_FILE=""
	CURRENT_SHELL="${SHELL##*/}"
	case $CURRENT_SHELL in
	    bash) CONFIG_FILE="$HOME_DIR/.bashrc" ;;
	    zsh) CONFIG_FILE="$HOME_DIR/.zshrc" ;;
	    ksh) CONFIG_FILE="$HOME_DIR/.kshrc" ;;
	    fish) CONFIG_FILE="$HOME_DIR/.config/fish/config.fish" ;;
	    csh|tcsh) CONFIG_FILE="$HOME_DIR/.cshrc" ;;
	    sh) CONFIG_FILE="$HOME_DIR/.profile" ;;  # /bin/sh config files depend on the system and actual shell linked to /bin/sh
	    *) echo "Unknown or less commonly used shell: $CURRENT_SHELL"; CONFIG_FILE="Unknown" ;;
	esac

	if [[ -f $CONFIG_FILE ]]; then
		log "Info    -    Configuration file is located at $CONFIG_FILE"
	else
		log "Info   -    Configuration file should be located at $CONFIG_FILE but cannot be found..."
		if [[ -n "${logged_user}" ]]; then
			log "Info    -    We'll create it..."; touch $CONFIG_FILE
		else
			log "Error   -    Aborting since we can't set environment variables without configuration file..."; exit 1
		fi
	fi
}

# Function to identify the logged-in user
default_user() {
	#log "Info    - Identifying the default user"... 
	logged_user=$(stat -f "%Su" /dev/console)
	if [ "$EUID" -ne 0 ]; then # Standard sser
		log "Info    -    Current user is $logged_user" 
	else #Root User
		log "Error    - This script should not run as root, aborting..."
		if [[ -n "${logged_user}" ]]; then handle_error "Info    - Please run it with $logged_user"; fi
	fi

	HOME_DIR=$(dscl . -read /Users/$logged_user NFSHomeDirectory | awk '{print $2}')
	if [[ ! -d ${HOME_DIR} ]]; then log "Error   -    Home directory for "$logged_user" does not exist at "$HOME_DIR"! Aborting..."; exit 1; else log "Info    -    Home directory for "$logged_user" is located at "$HOME_DIR""; fi
}

cacert_integrity_check(){	
	log "Info    -    Checking $customcacert integrity..."
  local cacert_file=$1
  local n=0
  local cert_file

  # Read the entire cacert.pem file into a variable
	pem_contents=$(<"$cacert_file")

	# Initialize an empty array to hold individual certificates
	certificates=()

	# Use a while loop to extract each certificate and store it in an array
	while [[ "$pem_contents" =~ (-----BEGIN CERTIFICATE-----(.*?)
	-----END CERTIFICATE-----) ]]; do
	    # Append the matched certificate to the certificates array
	    certificates+=( "${BASH_REMATCH[0]}" )

	    # Remove the processed certificate from the pem_contents
	    pem_contents=${pem_contents#*-----END CERTIFICATE-----}
	done

	# Now process each certificate using openssl
	for cert in "${certificates[@]}"; do
	    # If you need to decode the certificate with openssl, you can do like this:
	    echo "$cert" | openssl x509 -noout -text
	done
	sleep 600
}


# Function to add the internal Root CAs from the OS Keychain Manager to the certificate stores (cacert.pem)
trustca() {
	cacert="$1"		# $1 is the pem files to be patched... where $2 is the name of the application requiring it
	if [ ! -f "$cacert" ]; then
	  log "Error   -    Custom Certificate Store could not be located at "$cacert"... It will not be patched. Error was reported in the logfile"; exit 1
	else
	  log "Info    -    Custom Certificate Store in "$cacert" is being patched with Internal Root CAs from the MacOS Keychain Access:"
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
	        log "Success -       $certname is now trusted in our custom certificate store"
	    else
	    	log "Info    -       $certname was already trusted in our custom certificate store"
	    fi
	  done <<< "$IntCAList"
	  log "Success - Custom Certificate Store now includes our internal Root CAs"
	fi
}

shell_var(){
	log "Info    -    Looking for CA related Environment Variables in $CONFIG_FILE"
	# List of variables to check
	variables=("GIT_SSL_CAINFO" "CURL_CA_BUNDLE" "REQUESTS_CA_BUNDLE" "AWS_CA_BUNDLE" "NODE_EXTRA_CA_CERTS" "SSL_CERT_FILE" )

	# Function to check if a file contains a specific variable
	contains_variable() {
	  local variable=$1
	  if grep -q "^export $variable=" "$CONFIG_FILE"; then
	    log "Info     -      $variable is set in $CONFIG_FILE"
	    log "Info     -          $(cat "$CONFIG_FILE" | grep "$variable")"
	    log "Info     -          If this entry is incorrect, please correct it manually with a text editor..."
	  else
	    log "Warning  -      $variable was not set in $CONFIG_FILE. Let's add it..."
 		echo "export "$variable"=\""$customcacert"\"" >> $CONFIG_FILE; sleep 1
 		# Check again, if we were able to add the variable
 		if grep -q "^export $variable=" "$CONFIG_FILE"; then
		    log "Info     -         $variable is now set in $CONFIG_FILE"
		    log "Info     -         $(cat "$CONFIG_FILE" | grep "$variable")"
	    else
	    	log "Error    -         $variable could not be added to $CONFIG_FILE! Aborting..."; exit 1 
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
	log "Info    - Downloading and/or locating custom PEM certificate" 
	# Create the directory for storing cacert.pem unless existing
	if [[ -d "$HOME_DIR/.config/cacert/" ]]; then
	else
		mkdir -p "$HOME_DIR/.config/cacert/"
	fi

	# check if cacert.pem already exists...
	customcacert="$HOME_DIR/.config/cacert/cacert.pem"
	if [[ -f "$HOME_DIR/.config/cacert/cacert.pem" ]]; then
		log "Info    -    Custom PEM certificate exists already. It will not be retrieved from the internet..."
	else
		cd "$HOME_DIR/.config/cacert/"; curl -k -L -O "$cacertURL" >/dev/null 2>&1 # We download it again...
		if [[ $? -ne 0 ]]; then log "Error    -    Something went wrong with downloading cacert.pem from "$cacertURL"... Please troubleshoot the issue or contact support. Aborting!"; exit 1; fi
		if [[ ! -f "$HOME_DIR/.config/cacert/cacert.pem" ]]; then log "Error    -    Something went wrong with downloading cacert.pem from "$cacertURL"... Please troubleshoot the issue or contact support. Aborting!"; exit 1; fi
	fi
	log "Info    -    Custom PEM certificate can be found at "$customcacert""
}

###########################   Script SWITCHES   ###########################
# Switches and Executions for the initial call (regardless of when)
while [[ $# -gt 0 ]]; do
  case $1 in
    --help|-h) help ;;
    --uninstall|-u) uninstall ;;
   *) ;;
  esac
  shift
done

### Requirement:
log "Info    - Verifying requirements..."

# Check if the operating system is Darwin (macOS)
if [ "$(uname)" != "Darwin" ]; then log "Error   - This Script is meant to run on macOS, not on: $(uname -v)"; exit 1; fi
log "Info    -    Running on $(get_macos_version)"

# Let's identify the logged in or default user and it's home directory...
default_user

# Let's identify the default Shell interpreter and associated config file for that user...
shell_config

# Let's download cacert.pem 
cacert_download

# Check if the certificate authority file is valid
# cacert_integrity_check $customcacert

# List the Internal Root CAs and patch cacert.pem with internal Root CAs
source "$scriptpath/Keychain_InternalCAs.sh" --silent		# This command will invoke the script with variable $IntCAList which list the names of Internal Signing Root CAs from the Keychain Access in MacOS
trustca "$customcacert"

# Check AGAIN if the certificate authority file is valid after patching...
# cacert_integrity_check $customcacert

# Let's inspect the file for existing environement variables & Let's reference this cacert.pem in the Shell Interpreter config file
shell_var

source $CONFIG_FILE
cd "$scriptpath"



