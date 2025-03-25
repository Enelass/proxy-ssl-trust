#!/bin/zsh

#################### Written by Florian Bidabe #####################################
#                                                                                  #
#  DESCRIPTION: The purpose of this script / hotfix is to fix certificate trust    #
#               issues where any client fails to connect as it does not trust      #
#               MacOS Certificate Authorities found in the Keychain (System Store) #
#               issued internally. The script adds the Base64 Root                 #
#               certificate authorities to the various client certificate store    #
#               conventionally named (cacert.pem)                                  #
#               Future release will support setting this as a Daemon and could     #
#               support Java keystore, or DER if use-cases are found.              #
#               Also it will support attribute to uninstall, help, and scanall     #
#  INITIAL RELEASE DATE: 19-Sep-2024                                               #
#  AUTHOR: Florian Bidabe                                                          #
#  LAST RELEASE DATE: 19-Sep-2024                                                  #
#  VERSION: 1.3                                                                    #
#  REVISION:                                                                       #
#                                                                                  #
#                                                                                  #
####################################################################################



#################################   Variables     ####################################
AppName="CATrustDaemon"
version="1.3"
scriptpath=$(pwd)

if [ "$EUID" -ne 0 ]; then # Standard User
	# Directory for files in User-Context. It cannot patch the system
	CDir="$HOME/Applications/$AppName"
	teefile="$CDir/$AppName.log"
else #Root User
	# Directory for files in System-Context. It will patch both user and system
	CDir="/usr/local/etc/$AppName"
	teefile="/var/log/$AppName.log"
fi

####################################### Defining functions ###########################	

# Logging function
timestamp() { date "+%Y-%m-%d %H:%M:%S" }
log() { local message="$1"; echo "$(timestamp) $message" | tee -a $teefile }
logonly() { local message="$1"; echo "$(timestamp) - $message" >> $teefile }
handle_error() { local message="$1"; log "$message"; exit 1 } # Error handling function

# Display the Help Menu
help() {
    script="$1"
    clear
	echo -e "Summary: This script is designed to manage and patch certificate stores on macOS systems.\nIt's primary function is to ensure that clients trust internal Certificate Authorities.\n"
	echo -e "Author: florian@photonsec.com.au\t\tgithub.com/Enelass\nRuntime: currently running as $(whoami)\nVersion: $version\n"
	echo -e "Usage: $script [OPTION]..."
	echo -e "  --help, -h\tDisplay this help menu...\n"
	echo -e "  --list, -l\tOnly list Signing root CA certificates from the MacOS Keychain Access, This is usefull if you want to check what Root CAs are supplied with the SOE, or what Root CAs are performing SSL Inspection"
	echo -e "  --scan, -s\tOnly scan for PEM Certificate Stores on the system. I will not patch it!\n\t\tThis can be useful if you're looking for a software certificate store but do not know where to find it\n"
	echo -e "  --var\t\tSet default shell environement variable to a known PEM Certificate Store containing internal and Public Root CA... This is usefull if you need an easy fix for common CLI and within the user-context only...\n"
  echo -e "  --var_uninstall\tIf this script behaved erratically or corrupted anything after using --var, we can revert back to the original/vanilla state\n"
	echo -e "  --patch, -p\tOnly patch known PEM Certificate Stores... This is usefull if you need to re-patch known certificate stores previously scanned but without scanning again since it is time consuming...\n"
  echo -e "  --patch_uninstall\tIf this script behaved erratically or corrupted anything after using --patch, we can revert back to the original/vanilla state\n"
	echo -e "  By default, if no switches are specified, it will run in both User and System contexts if the user is priviledged, or user context only if unprivileged...\n  It will only look for PEM Files (certicate stores used by various clients, e.g. AWSCli, AzureCLI, Python, etc...)"
	exit 0
}

# Switch to download the latest PEM Certificate Store (cacert.pem) from the internet (curl.se)
# then patch it and reference it from the user's Shell config file (e.g. ~/.zshrc)
var() {
	switch="Set Shell and Env Variables to custom PEM certificate file"
	var=1 # Do scan PEM Certificate Stores
}

# Switch to remove Environement variable from the user's Shell config and delete the custom PEM certificate store from the user's directory
var_uninstall() {
	switch="Revoking Shell and Env Variables + Deletion of custom PEM certificate file"
	var_uninstall=1 # Do scan PEM Certificate Stores
}

# Switch to scan-only new pem files, but do not patch
scan() {
	switch="PEM Scanning (User and System)"
	pemscan=1 # Do scan PEM Certificate Stores
}

# Switch to list-only signing Root CAs certificates in Keychain Access
list() {
	switch="Internal Root CAs listing from Keychain Access"
	KAlist=1 # List MacOS Keychain Access certificates... 
}

# Switch to patch-only known (previously scanned) pem files / Quick mode
patch() {
	switch="Internal Root CAs listing & PEM Patching"
	pempatch=1 #pempatch=1 implies KAlist=1 so no need to explicitely define it as default, we'll need it for patching anyway
}

# Switch to patch-only known (previously scanned) pem files / Quick mode
patch_uninstall() {
	switch="PEM Patching uninstallation"
	patch_uninstall=1 #pempatch=1 implies KAlist=1 so no need to explicitely define it as default, we'll need it for patching anyway
}

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


###################################### Checking Requirements ###########################################
###########################   Script SWITCHES   ###########################
# Switches and Executions for the initial call (regardless of when)
if [[ $# -gt 1 ]]; then
  echo "Error: too many arguments. Please supply only one argument or none..." >&2; exit 1
fi
if [[ $# -eq 0 ]]; then
  # No switches were supplied, exit normally
  default
fi
while [[ $# -gt 0 ]]; do
  case $1 in
    --help|-h) help ;;
    --list|-l) list ;;
		--var) var ;;
		--var_uninstall) var_uninstall ;;
    --scan|-s) scan ;;
    --patch|-p) patch ;;
    --patch_uninstall) patch_uninstall`` ;;
    *) echo "Error: unknown option '$1'" >&2; exit 1 ;;
  esac
  shift
done


# If the log files, doesn't exist, we'll create it
if [ ! -f "$teefile" ]; then
  touch "/tmp/$AppName.log"
  teefile="/tmp/$AppName.log"
fi


# Welcoming stdin for unprivileged user
if [ "$EUID" -ne 0 ]; then
	clear
  echo "___________________________ - Unprivileged - _____________________________________________________________________________"
	log "Info    - This script resolves certificate trust issues by adding Base64 Root certificate authorities"
	log "          to the client certificate store (cacert.pem). This addresses situations where clients fail "
	log "          to connect due to lack of trust of internal Certificate Authorities"
	log "          found in the Keychain (MacOS System Certificate Store)"
	log "          The purpose of this script is to save days if not weeks of productivity loss due to the"
	log "          lenghty troubleshooting of certificate trust and proxy issues"
	log "Info    -    Logs are saved in $teefile"
	log "Info    - Execution specifics..."
	log "Info    -    Switch selection: $(printf "%s=%s "var "${var}" var_uninstall "${var_uninstall}" "${var}" KAlist "${KAlist}" pemscan "${pemscan}" pempatch "${pempatch}" patch_uninstall "${patch_uninstall}")"
	log "Info    -    Switch description: $switch"
	log "Info    -    This script is being executed by `whoami` / EUID: $EUID"
	# Scanning and Patching requires user elevation...
	if [[ "$pemscan" || "$pempatch" || "$patch_uninstall" ]]; then
  	log "Info    - User elevation is required. Please run again as root or sudo"
  	exit 1
	fi
fi

# Welcoming stdin for elevated user
if [ "$EUID" -eq 0 ]; then
	echo -e "\n"
	echo "___________________________ - Elevated - ________________________________________________________________________________"
	log "Info    - This script resolves certificate trust issues by adding Base64 Root certificate authorities"
	log "          to the client certificate store (cacert.pem). This addresses situations where clients fail "
	log "          to connect due to lack of trust of internal Certificate Authorities"
	log "          found in the Keychain (MacOS System Certificate Store)"
	log "          The purpose of this script is to save days if not weeks of productivity loss due to the"
	log "          lenghty troubleshooting of certificate trust and proxy issues"
	log "Info    -    Logs are saved in $teefile"
	log "Info    -    Config files will be stored in $CDir/"
	log "Info    - Execution specifics..."
	log "Info    -    Switch selection: $(printf "%s=%s "var "${var}" var_uninstall "${var_uninstall}" "${var}" KAlist "${KAlist}" pemscan "${pemscan}" pempatch "${pempatch}" patch_uninstall "${patch_uninstall}")"
	log "Info    -    Switch description: $switch"
	log "Info    -    This script is running elevated as `whoami`"
	logged_user=$(stat -f "%Su" /dev/console)
	if [[ ! -z "${logged_user-}" ]]; then log "Info    -    Logged-in user is $logged_user"; fi
fi

log "Info    - Verifying System requirements..."
# Check if the operating system is Darwin (macOS)
if [ "$(uname)" != "Darwin" ]; then log "Error   - This Script is meant to run on macOS, not on: $(uname -v)"; exit 1; fi
log "Info    -      Running on $(get_macos_version)"

# Set proxy in case we need to download and install anything....
export HTTPS_PROXY=http://cba.proxy.prismaaccess.com:8080; export HTTP_PROXY=http://cba.proxy.prismaaccess.com:8080
# Let's search for cacert.pem
PATH="/opt/homebrew/bin:$PATH"

# Check if Curl and Homebrew are installed
if ! command_exists brew; then handle_error "Info    - Homebrew is not installed. Please install it via Self-Service"; exit 1; else log "Info    -      $(brew --version | awk {'print $1, $2'}) is already installed."; fi
if ! command_exists curl; then log "Info    - curl is not installed. Installing curl..."; attempt_install curl; else log "Info    -      $(curl -V | head -n 1 | awk '{print $1, $2}') is already installed."; fi


###########################   File creation and Db of cacert.pem on the system   ###########################
cacert_syslist="$CDir/cacert_syslist.csv"						# A new generated list of cacert.pem files found in the system context
cacert_userlist="$CDir/cacert_userlist.csv"					# A new generated list of cacert.pem files found in the user context
cacert_sysdb="$CDir/cacert_sysdb.csv" 							# The system Db file (with metadata)
cacert_userdb="$CDir/cacert_userdb.csv" 						# The user Db file (with metadata)
cacertdb="$CDir/cacertdb.csv" 											# The Final Db file (with metadata), combining user and system files
prevcacert_sysdb="$CDir/cacert_sysdb.backup.csv"		# The previous System Db File we use to compare against current to skip patched cacert.pem
prevcacert_userdb="$CDir/cacert_userdb.backup.csv"	# The previous user Db File we use to compare against current to skip patched cacert.pem
prevcacertdb="$CDir/cacertdb.backup.csv"						# The previous Db File we use to compare against current to skip patched cacert.pem




############################  Env Variables and Custom downloaded PEM #############################
if [[ ${var} -eq 1 ]]; then ./PEM_Var.sh; fi 
if [[ ${var_uninstall} -eq 1 ]]; then ./PEM_Var.sh --uninstall; fi 


############################  SCANNING MacOS PEM Files #############################
if [[ ${pemscan} -eq 1 ]]; then
	log "Info    -     We will now proceed to scan the MacOS volume and look for PEM certificate stores"
	source ./PEM_Scanner.sh
	if [[ ! -f "$cacertdb" ]]; then
		log "Error   - Scanning appear to have failed: cannot find a list of certificate store (PEM files) to scan at $cacertdb...\n\t\t\t      Please run this script again with the --scan switch or no switches to force a new scan"
		exit 1 
	fi
	log "Info    -     Opening the list of found pem files on your system in your default CSV editor"
	open $(dirname "$cacertdb"); open $cacertdb; open $teefile
fi

##################  LISTING Internal Root CA from Keychain #######################
if [[ ${KAlist} -eq 1 ]]; then
	log "Info    -     We will now look for Internal Root CA in the Keychain Access. "
	source ./Keychain_InternalCAs.sh --quiet
	if [[ -z "${IntCAList-}" ]]; then log "Error    -    We couldn't find a list of Internal signing Root CAs to add to the various PEM certificate stores"; exit 1; fi
fi

######################  PATCHING PEM Certificate Stores ##############################
if [[ ${pempatch} -eq 1 ]]; then source ./PEM_Patcher.sh; fi
if [[ ${patch_uninstall} -eq 1 ]]; then source ./PEM_Patcher.sh --uninstall; fi



# Truncate Log file to insure it isn't ever growing. Capped at 10,000 lines of codes
tail -n 10000 "$teefile" > "${teefile}.tmp" && mv "${teefile}.tmp" "$teefile"