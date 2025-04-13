#!/bin/zsh

#################### Written by Florian Bidabe #####################################
#                                                                                  #
#  DESCRIPTION: The purpose of this suite of scripts is to fix certificate trust   #
#               issues where clients (CLI mostly but also a few GUIs) fail to      #
#               connect as it does not trust Internal Certificate Authorities      #
#               found in KeychainAccess.                                           #
#               This script invokes other scripts to detect proxy settings and     #
#               create persistent connectivity for the current user.               #
#               It also support a variety of swithces for advanced troubleshooting #
#  INITIAL RELEASE DATE: 19-Sep-2024                                               #
#  AUTHOR: Florian Bidabe                                                          #
#  LAST RELEASE DATE: 30-Mar-2025                                                  #
#  VERSION: 1.7                                                                    #
#  REVISION:    Major revamp, better stdout, better logging, and bug fixes         #
#                                                                                  #
#                                                                                  #
####################################################################################



#################################   Variables     ####################################
AppName="Proxy_SSL_Trust"
version="1.7"
script_dir=$(dirname $(realpath $0))
teefile="/tmp/$AppName.log"
invoked=true	# To instruct other scripts that we sourced them... 
if [[ -z ${logI-} ]]; then source "$script_dir/stderr_stdout_syntax.sh"; fi
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
  echo -e "  --help, -h\t\tShow this help menu"
  echo -e "  --version\t\tShow the version information"
	echo -e "  --list, -l\t\tList all the signing Root CAs from the MacOS Keychain Access, This is usefull if you want to check what Root CAs
	\t\tare supplied with the SOE, or what Root CAs are performing SSL Inspection"
	echo -e "  --scan, -s\t\tOnly scan for PEM Certificate Stores on the system. I will not patch it!\n\t\t\tThis can be useful if you're looking for a software certificate store but do not know where to find it"
	echo -e "  --var_uninstall\tRevert any changes made by --var, restoring to the original state"
	echo -e "  --var\t\t\tSet default shell environement variable to a known PEM Certificate Store containing internal and Public Root CA...
	\t\tThis is usefull if you need an easy fix for common CLI and within the user-context only..."
	echo -e "  --patch_uninstall\tRevert any changes made by --patch, restoring to the original state"
	echo -e "  --patch, -p\t\t(For Testing Only) Patch known PEM Certificate Stores (requires --scan) unless excluded...
	\t\tThis is usefull if you want to patch known certificate stores previously scanned (not recommended)..."
	echo -e "  By default, if no switches are specified, it will run in both User and System contexts if the user is priviledged, or user context only if unprivileged...\n  It will only look for PEM Files (certicate stores used by various clients, e.g. AWSCli, AzureCLI, Python, etc...)"
	exit 0
}



# Switch to list-only signing Root CAs certificates in Keychain Access
list() {
	switch="Internal Root CAs listing from Keychain Access"
	KAlist=1 # List MacOS Keychain Access certificates... 
}

# Switch to download the latest PEM Certificate Store (cacert.pem) from the internet (curl.se) then patch it and reference it from the user's Shell config file (e.g. ~/.zshrc)
var() {
	switch="Set SSL Env Variables to Custom Certificate Store"
	var=1 # Set SSL Env Variables to Custom Certificate Store
}

# Switch to remove Environement variable from the user's Shell config and delete the custom PEM certificate store from the user's directory
var_uninstall() {
	switch="Revoking Shell and Env Variables + Deletion of custom PEM certificate file"
	var_uninstall=1 # Revoking files and unset variables from --var
}

# Switch to scan-only new pem files, but do not patch
scan() {
	switch="PEM Scanning"
	pemscan=1 # Do scan PEM Certificate Stores in User and System context
}

# Switch to revert all changed made by --scan. It'll delete the file generated by --scan  
scan_uninstall() {
	switch="PEM Scanning uninstallation"
	scan_uninstall=1 # Remove all files created by --scan
}

# Switch to patch-only known (previously scanned) pem files / Quick mode
patch() {
	switch="Internal Root CAs listing & PEM Patching"
	pempatch=1 #pempatch=1 will invoke Keychain_InternalCAs.sh so no need to set KAlist=1 as it'd be redundant...
}

# Switch to restore all pem files that have been patched and revert from --path
patch_uninstall() {
	switch="PEM Patching uninstallation"
	patch_uninstall=1
}

# Switch to test proxy and pac file & install Alpaca as a daemon
proxy() {
	switch="Setting up proxy and PAC file"
	proxy=1 #pempatch=1 will invoke Keychain_InternalCAs.sh so no need to set KAlist=1 as it'd be redundant...
}

# Switch to patch-only known (previously scanned) pem files / Quick mode
proxy_uninstall() {
	switch="Proxy and PAC uninstallation"
	proxy_uninstall=1
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
            logS "$package installed successfully."
            return 0
        fi
        logW "Failed to install $package. Attempts left: $attempts"
        attempts=$((attempts - 1))
    done
    logE "Failed to install $package after 2 attempts. Exiting..."
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
  	--version|-v) echo "$0 version: $version"; exit 0 ;;
    --help|-h) help ;;
    --list) list ;;
		--var) var ;;
		--var_uninstall) var_uninstall ;;
    --scan) scan ;;
		--scan_uninstall) scan_uninstall ;;
    --patch) patch ;;
    --patch_uninstall) patch_uninstall ;;
		--proxy) proxy ;;
		--proxy) proxy_uninstall ;;
    *) echo "Error: unknown option '$1'" >&2; exit 1 ;;
  esac
  shift
done

# Welcoming stdin for unprivileged user
if [ "$EUID" -ne 0 ]; then
	clear
  echo "___________________________ - Unprivileged - _____________________________________________________________________________"
	logI "This script resolves certificate trust issues by adding Base64 Root certificate authorities"
	log "          to the client certificate store (cacert.pem). This addresses situations where clients fail "
	log "          to connect due to lack of trust of internal Certificate Authorities"
	log "          found in the Keychain (MacOS System Certificate Store)"
	log "          The purpose of this script is to save days if not weeks of productivity loss due to the"
	log "          lenghty troubleshooting of certificate trust and proxy issues"
	logI "   Logs are saved in $teefile"
	logI "Execution specifics..."
	# logI "   Switch selection: $(printf "%s=%s "var "${var}" var_uninstall "${var_uninstall}" "${var}" KAlist "${KAlist}" pemscan "${pemscan}" pempatch "${pempatch}" patch_uninstall "${patch_uninstall}")"
	logI "   Switch description: $switch"
	logI "   This script is being executed by `whoami` / EUID: $EUID"
	# Scanning and Patching requires user elevation...
	if [[ "$pemscan" || "$pempatch" || "$patch_uninstall" ]]; then
  	logE "User elevation is required. Please run again as root or sudo"
	fi
fi

# Welcoming stdin for elevated user
if [ "$EUID" -eq 0 ]; then
	clear
	echo -e "\n"
	echo "___________________________ - Elevated - ________________________________________________________________________________"
	logI "This script resolves certificate trust issues by adding Base64 Root certificate authorities"
	log "          to the client certificate store (cacert.pem). This addresses situations where clients fail "
	log "          to connect due to lack of trust of internal Certificate Authorities"
	log "          found in the Keychain (MacOS System Certificate Store)"
	log "          The purpose of this script is to save days if not weeks of productivity loss due to the"
	log "          lenghty troubleshooting of certificate trust and proxy issues"
	logI "   Logs are saved in $teefile"
	logI "Execution specifics..."
	# logI "   Switch selection: $(printf "%s=%s "var "${var}" var_uninstall "${var_uninstall}" "${var}" KAlist "${KAlist}" pemscan "${pemscan}" pempatch "${pempatch}" patch_uninstall "${patch_uninstall}")"
	logI "   Switch description: $switch"
	logI "   This script is running elevated as `whoami`"
	logged_user=$(stat -f "%Su" /dev/console)
	if [[ ! -z "${logged_user-}" ]]; then logI "   Logged-in user is $logged_user"; fi
fi

logI "Verifying System requirements..."
# Check if the operating system is Darwin (macOS)
if [ "$(uname)" != "Darwin" ]; then log "Error   - This Script is meant to run on macOS, not on: $(uname -v)"; exit 1; fi
logI "     Running on $(get_macos_version)"

# Check if Curl and Homebrew are installed
if ! command_exists brew; then logE " Homebrew is not installed. Please install it..."; else logI "     $(brew --version | awk {'print $1, $2'}) is already installed."; fi
if ! command_exists curl; then logI "cURL is not installed. Installing curl..."; attempt_install curl; else logI "     $(curl -V | head -n 1 | awk '{print $1, $2}') is already installed."; fi

#########################  Proxy and PAC File setup ##############################
if [[ ${proxy} -eq 1 ]]; then source "$script_dir/proxy/connect_noproxy.sh"; exit; fi
if [[ ${proxy_uninstall} -eq 1 ]]; then source "$script_dir/proxy/AlpacaSetup.sh" --uninstall; exit; fi


########################  Env Variables and Custom downloaded PEM #################
if [[ ${var} -eq 1 ]]; then source "$script_dir/SSL/PEM_Var.sh"; exit; fi 
if [[ ${var_uninstall} -eq 1 ]]; then source "$script_dir/SSL/PEM_Var.sh" --uninstall; exit; fi 


############################  SCANNING MacOS PEM Files #############################
if [[ ${pemscan} -eq 1 ]]; then source "$script_dir/SSL/PEM_Scanner.sh"; exit; fi
if [[ ${scan_uninstall} -eq 1 ]]; then source "$script_dir/SSL/PEM_Scanner.sh" --uninstall; exit; fi


##################  LISTING Internal Root CA from Keychain ########################
if [[ ${KAlist} -eq 1 ]]; then
	logI "    We will now look for Internal Root CA in the Keychain Access."; source "$script_dir/SSL/Keychain_InternalCAs.sh" --quiet
	if [[ -z "${IntCAList-}" ]]; then logE "   We couldn't find a list of Internal signing Root CAs to add to the various PEM certificate stores"; fi
fi

######################  PATCHING PEM Certificate Stores ##############################
if [[ ${pempatch} -eq 1 ]]; then source "$script_dir/SSL/PEM_Patcher.sh"; exit; fi
if [[ ${patch_uninstall} -eq 1 ]]; then source "$script_dir/SSL/PEM_Patcher.sh" --uninstall; exit; fi





# Truncate Log file to insure it isn't ever growing. Capped at 10,000 lines of codes
tail -n 10000 "$teefile" > "${teefile}.tmp" && mv "${teefile}.tmp" "$teefile"