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
# List of variables to check
variables=("GIT_SSL_CAINFO" "CURL_CA_BUNDLE" "REQUESTS_CA_BUNDLE" "AWS_CA_BUNDLE" "NODE_EXTRA_CA_CERTS" "SSL_CERT_FILE")

source ./play.sh
clear

# If not invoked/sourced by another script, we'll set some variable for standalone use otherwise this would be ineritated by the source script along with $teefile...
if [[ -z "${teefile-}" ]]; then 
    source ./stderr_stdout_syntax.sh
    echo -e "\n\nSummary: The purpose of this script is to provide various CLI on MacOS with environment variables referencing a custom PEM certificate store including public and internal Root
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
	logI "    Requesting uninstallation"
	default_user; shell_config
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
	exit 0
}


# Function to identify the shell interpreter and its config file
shell_config() {
	echo ""; logI " Identifying the Shell interpreter" 
	DEFAULT_SHELL=$SHELL 									# Determine default shell
	CURRENT_SHELL=$(ps -p $$ -o comm=) 		# Determine current shell
	if [[ "$DEFAULT_SHELL" ==  "$CURRENT_SHELL" ]]; then
		logI "    Default Shell: $DEFAULT_SHELL matches the current Shell: $CURRENT_SHELL"
	else
		logE "    Default Shell: $DEFAULT_SHELL does not match the current Shell: $CURRENT_SHELL"
		logI "    We'll abort, otherwise we'd set the environement variables in a Shell interpreters that isn't used by the user"
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
		logS "    Configuration file was found at $CONFIG_FILE"
	else
		logW "    Configuration file should be located at $CONFIG_FILE but it does not exist..."
		if [[ -n "${logged_user}" ]]; then
			logI "    We'll create it..."; touch $CONFIG_FILE
		else
			logE "    Aborting since we can't set environment variables without configuration file..."
		fi
	fi
}

# Function to identify the logged-in user
default_user() {
	#log "Info    - Identifying the default user"... 
	logged_user=$(stat -f "%Su" /dev/console)
	if [ "$EUID" -ne 0 ]; then # Standard sser
		logS "    Logged-in user is identified as $logged_user" 
	else #Root User
		logW " This script should not run as root, aborting..."
		if [[ -n "${logged_user}" ]]; then logE " Please run it with $logged_user"; fi
	fi

	HOME_DIR=$(dscl . -read /Users/$logged_user NFSHomeDirectory | awk '{print $2}')
	if [[ ! -d ${HOME_DIR} ]]; then
		logE "    Home directory for "$logged_user" does not exist at "$HOME_DIR"! Aborting..."
	else logS "    Home directory for "$logged_user" is located at "$HOME_DIR""; fi
}


# Function to add the internal Root CAs from the OS Keychain Manager to the certificate stores (cacert.pem)
trustca() {
	cacert="$1"		# $1 is the pem files to be patched... where $2 is the name of the application requiring it
	if [ ! -f "$cacert" ]; then
	  logW "    Custom Certificate Store could not be located at "$cacert"..."
	  logE "    It will not be patched. Error was reported in the logfile"
	else
	  logI "    It will be patched with Internal Root CAs from the MacOS Keychain Access:"
	  # We keep a vanilla cacert.pem as we'll use it to determine if a website isn't signed by a public CA
	  if [[ ! -f $cacert.public ]]; then cp $cacert $cacert.public; fi
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
	  done <<< "$IntCAList"
	  log "Success - Custom Certificate Store now includes our internal Root CAs"
	fi
}

shell_var(){
	log "Info    -    Looking for CA related Environment Variables in $CONFIG_FILE"
	# Function to check if a file contains a specific variable
	contains_variable() {
	  local variable=$1
	  if grep -q "^export $variable=" "$CONFIG_FILE"; then
	    logW "      ${GREENW}$variable${NC} was already set in $CONFIG_FILE"
	    logI "          $(cat "$CONFIG_FILE" | grep "$variable")"
	    logI "          If this entry is incorrect, please correct it manually with a text editor..."
	  else
	    logI "      ${GREENW}$variable${NC} was not set in $CONFIG_FILE. Let's add it..."
 		echo "export "$variable"=\""$customcacert"\"" >> $CONFIG_FILE; sleep 1
 		# Check again, if we were able to add the variable
 		if grep -q "^export $variable=" "$CONFIG_FILE"; then
		    logS "         $(cat "$CONFIG_FILE" | grep "$variable") has been added to the Shell config file..." 
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
	echo ""; logI " Downloading and/or locating custom PEM certificate" 
	# Create the directory for storing cacert.pem unless existing
	if [[ -d "$HOME_DIR/.config/cacert/" ]]; then
	else
		mkdir -p "$HOME_DIR/.config/cacert/"
	fi

	# check if cacert.pem already exists...
	customcacert="$HOME_DIR/.config/cacert/cacert.pem"
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
echo ""; logI " Verifying requirements..."

# Check if the operating system is Darwin (macOS)
if [ "$(uname)" != "Darwin" ]; then logE " This Script is meant to run on macOS, not on: $(uname -v)"; fi
logI "    Running on $(get_macos_version)"

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
# cacert_integrity_check.sh $customcacert

# Let's inspect the file for existing environement variables & Let's reference this cacert.pem in the Shell Interpreter config file
shell_var

source "$CONFIG_FILE"
cd "$scriptpath"



