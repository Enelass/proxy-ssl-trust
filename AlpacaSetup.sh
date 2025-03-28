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

#################################### Variables ####################################
testURL="https://google.com"		# Input here a website you know to be SSL intercepted. This serves to test where Alcapa is running as expected and making use of the PAC File.
version="v0.2"
scriptname="$0"

######################## A bit of epic music never hurts ##########################
source ./play.sh


########################## Standalone Exec - Specifics #############################
# If not invoked/sourced by another script, we'll set some variable for standalone use otherwise this would be ineritated by the source script along with $teefile...
if [[ -z "${teefile-}" ]]; then 
	AppName="ProxyAutoSetup"
	teefile="/tmp/$AppName.log"
	version=0.2

	# Logging function
	timestamp() { date "+%Y-%m-%d %H:%M:%S" }
	log() { local message="$1"; echo "$(timestamp) $message" | tee -a $teefile }				# Output to stdout & log file
	logonly() { local message="$1"; echo "$(timestamp) $message" >> $teefile }					# Output only to log file
	handle_error() { local message="$1"; log "$message"; exit 1 } # Error handling functions	# Output to stdout & log file + abort

	# Function to check if we're running on MacOS
	get_macos_version() { local product_name=$(sw_vers -productName); local product_version=$(sw_vers -productVersion); local build_version=$(sw_vers -buildVersion); echo "$product_name $product_version ($build_version)" }

    clear
    logonly "------------------------------ new execution ------------------------------"
    log "Summary - The purpose of this script is to check network interfaces for PAC file settings, ensure Alpaca proxy\n\t\t\t      is installed and running if a PAC file is being used, and manage necessary proxy configurations."
    log "Author  - florian@photonsec.com.au\t\tgithub.com/Enelass"
    log "Runtime - Currently running as $(whoami)"
    logonly "Info - This script was invoked directly... Setting variable for standalone use..."

    # Check if the operating system is Darwin (macOS)
	if [ "$(uname)" != "Darwin" ]; then handle_error "Error   - This Script is meant to run on macOS, not on: $(uname -v)"; fi
	log "Info    - Running on $(get_macos_version)"
fi

############################## Defining functions ##################################

connectivity_test() {
	log "Info    - We will now run some connectivity tests or revert the changes made before..."
	# Is the Shell instructed to use Alpaca proxy?
	if [[ $HTTPS_PROXY == "http://localhost:3128" || $https_proxy == "http://localhost:3128" ]]; then
		log "Info    -   The proxy env variable is set to http://localhost:3128"
	else
		log "Error   -   The proxy env variable is not set to http://localhost:3128... It should!"
	fi

	# Is Alpaca proxy running?
	if lsof -i -P -n -sTCP:LISTEN | grep alpaca > /dev/null 2>&1; then
		log  "Info    -   Alpaca is running on TCP $(lsof -i -P -n -sTCP:LISTEN | grep alpaca | head -n 1 | awk '{print $9}')"
	else
		log  "Error   -   Alpaca does not appear to be running... It should!"
	fi
	# Can we connect to...
	log "Info    -   Attempting to connect to "$testURL" via localhost:3128..."

	tries=3 ; success=0  # Number of attempts and Flag to indicate success
	for attempt in {1..$tries}; do
	    if curl -I "$testURL" > /dev/null 2>&1; then
	        log "Success - We connected just fine 👍 !"
	        success=1; break  # Exit the loop on success
	    else
	        log "Error   -     Attempt $attempt - We couldn't connect to $testURL !"
	    fi
	done
	# If we cannot connect, revert changes but if the connectivity flag is set, do not uninstall Alpaca!
	if (( success == 0 )); then
	    log "Error   - All attempts to connect to $testURL failed!"
	    if [[ -z ${test-} ]]; then
	        log "Info    -   Connection failed after multiple attempts, reverting changes..."
	        uninstall; unset uninst
	    fi
	fi
	exit 0
}


uninstall() {
	if [[ -n $uninst ]]; then log "Info    - Uninstall switch was called"; fi
	log "Info    -    Let's delete the Alpaca binaries, settings and env var ..."
	# Revert Shell Config file
	CONFIG_FILE_BAK=$(find $HOME -maxdepth 1 -name "*.pre-alpacasetup" 2>/dev/null)
	if [[ -n "$CONFIG_FILE_BAK" && -f "$CONFIG_FILE_BAK" && -f "$CONFIG_FILE" ]]; then
		mv $CONFIG_FILE_BAK $CONFIG_FILE
		if [ $? -eq 0 ]; then log "Info    -    $CONFIG_FILE hads been restored"; fi
		source $CONFIG_FILE
	fi

	# Uninstall Alpaca only if user requested a uninstall, otherwise we'll just clear the Shell config file (e.g. ~/.zshrc) from the introduced changes
	if [[ -n $uninst ]]; then
		log "Info    - Uninstall switch was called"
		brew services stop alpaca > /dev/null 2>&1
		brew untap samuong/alpaca > /dev/null 2>&1
		brew uninstall alpaca     > /dev/null 2>&1
		log "Info    -    Homebrew settings and tap for Alpaca were revoked..."
		if where alpaca > /dev/null 2>&1; then
			log "Info    -    Unfortunately, it did not remove its binary, we'll remove it if you're local admin or if you're part of the sudoers"
			log "             Please enter your admin password. If you cannot, simply cancel the elevation prompts and the script will continue..."
			rm -f $(where alpaca) 2>/dev/null
		fi
	fi
	exit 0
}


# Function to identify the logged-in user
default_user() {
	#log "Info    - Identifying the default user"... 
	logged_user=$(stat -f "%Su" /dev/console)
	if [ "$EUID" -ne 0 ]; then # Standard sser
		log "Info    -    The logged-in user is $logged_user"
	else #Root User
		log "Error   - This script should not run as root, aborting..."
		if [[ -n "${logged_user}" ]]; then handle_error "Info    - Please run it with $logged_user"; fi
	fi
	log "Info    - We will now instruct the user's Shell/Terminal CLI to use Alpaca as a proxy..."
	HOME_DIR=$(dscl . -read /Users/$logged_user NFSHomeDirectory | awk '{print $2}')
	if [[ ! -d ${HOME_DIR} ]]; then handle_error "Error   -    Home directory for "$logged_user" does not exist at "$HOME_DIR"! Aborting..."; else log "Info    -      Home directory for "$logged_user" is located at "$HOME_DIR""; fi
}

# Function to identify the shell interpreter and its config file
shell_config() {
	log "Info    -    Identifying the Shell interpreter" 
	DEFAULT_SHELL=$SHELL 					# Determine default shell
	CURRENT_SHELL=$(ps -p $$ -o comm=) 		# Determine current shell

	if [[ "$DEFAULT_SHELL" ==  "$CURRENT_SHELL" ]]; then
		log "Info    -      Default Shell: $DEFAULT_SHELL matches the current Shell: $CURRENT_SHELL"
	else
		log "Error   -      Default Shell: $DEFAULT_SHELL does not match the current Shell: $CURRENT_SHELL"
		handle_error "Info    -      We'll abort, otherwise we'd set the environment variables in a Shell interpreters that isn't used by the user"
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
	    *) handle_error "Unknown or less commonly used shell: $CURRENT_SHELL"; CONFIG_FILE="Unknown" ;;
	esac

	if [[ -f $CONFIG_FILE ]]; then
		log "Info    -      Configuration file is located at $CONFIG_FILE"
	else
		log "Info   -      Configuration file should be located at $CONFIG_FILE but cannot be found..."
		if [[ -n "${logged_user}" ]]; then
			log "Info    -    We'll create it..."; touch $CONFIG_FILE
		else
			handle_error "Error   -    Aborting since we can't set environment variables without configuration file..."
		fi
	fi
}

shell_var(){
	variables=("all_proxy" "http_proxy" "https_proxy" "no_proxy")
	log "Info    -    Let's look for Proxy related Environment Variables..."
	# Loop through each variable and check if it is set
	for var in "${variables[@]}"; do
	if [[ -n ${(P)var} ]];
		then setvar+=$(echo "$var is set to ${(P)var} - ")
		log "Info    -      $var is set to ${(P)var}"
	fi
	done
	if [[ -z ${setvar-} ]]; then
		log "Info    -      Proxy variables are not set in this session..."
	fi

	log "Info    -    Looking for Proxy related Environment Variables declared in $CONFIG_FILE"
	check_set_proxy_var "$CONFIG_FILE"
}

# Function to check if the variable is set in the configuration file
check_set_proxy_var() {
    local file=$1
    unset patchrc
    # check for pattern like http_proxy or https_proxy
    for var in "${variables[@]}"; do
        if grep -qiE "^(export )?$var=.*" "$file"; then
            log "Info    -      Found individual entry: $(cat "$file" | grep -E "^(export )?$var=.*" | xargs)"
            log "Info    -      We will delete these individual entries"
            log "Info    -      This serves to consolidate and avoid issues with conflicties proxy settings"
           patchrc=true  # Delete the individual entries since we want to set one entry for all
        fi
    done
    
    # Also check for pattern like {all,http,https}_proxy
    if ! grep -qiE "^(export ){all,http,https}_proxy=http://localhost:3128" "$file"; then
        log "Info    -      Could not find the right proxy variable for Alpaca in "$file""
        patchrc=true 	# We couldn't find the right setting, so we'll add it
    fi

    if [[ -n $patchrc ]]; then
    	log "Info    -      We need to patch $CONFIG_FILE to add a unique environment variable for Alpaca:"
    	log "Info    -      We'll append this to the file, export {all,http,https}_proxy=http://localhost:3128"
    	log "Info    -      Ensuring we have a back-up for $CONFIG_FILE prior to making changes..."
        CONFIG_FILE_BAK="$CONFIG_FILE.pre-alpacasetup"
        cp -n "$CONFIG_FILE" "$CONFIG_FILE_BAK" > /dev/null 2>&1
        if [[ -f "$CONFIG_FILE.pre-alpacasetup" ]]; then log "Info    -      Backup file can be found at "$CONFIG_FILE_BAK""; fi
        sed -i '' '/^export.*_proxy=/d' "$file"
        echo 'export {all,http,https}_proxy=http://localhost:3128' >> "$CONFIG_FILE"
        source $CONFIG_FILE
    else
    	log "Info    -      The right environment variable for Alpaca was already found in $CONFIG_FILE"
    	log "Info    -          export {all,http,https}_proxy=http://localhost:3128"
    fi
}

install_alpaca() {
	if ! command -v alpaca > /dev/null 2>&1; then	# If Alpaca is not installed...
	log "Info    - Alpaca is not installed..."
	
	# Check if Homebrew is installed as we neet it to install Alpaca...
	if ! command -v brew > /dev/null 2>&1; then handle_error "Error   - This script requires Homebrew, please install it...\nIf you're corporate, you might have it packaged by your provisioning/SOE team (e.g. JAMF)\nOtherwise, you can install it as per: https://brew.sh/"; else log "Info    -   We'll attempt installing it with $(brew --version)"; fi
	
	# Attempt installing Alpaca 3x times
	brew tap samuong/alpaca
	attempt_install samuong/alpaca/alpaca
	
	# Check if Alpaca was sucessfully installed (normally yes otherwise the attempt_install would have exited 1)
	if command -v alpaca > /dev/null 2>&1; then
		log "Info    - $(alpaca --version) is now installed"
		brew services start alpaca > /dev/null 2>&1
	else
		handle_error "Error - We failed installing Alpaca, please install it manually as per: https://github.com/samuong/alpaca"
	fi
	# If Alpaca is installed...
	else
		log "Info    - $(alpaca --version) is installed"
		log "Info    -    Checking if Alpaca is running and listening..."
		if lsof -i -P -n -sTCP:LISTEN | grep alpaca > /dev/null 2>&1; then
			  # portnumber=$(lsof -i -P -n -sTCP:LISTEN | grep alpaca | head -n 1 | awk '{print $9}' | sed -E 's/.*:([0-9]*)/\1/')
			  # pid=$(lsof -i :3128 -P -n -Fp | grep -o 'p[0-9]*' | cut -c 2-)
			  # log  "Info    -    Alpaca is running on TCP $(lsof -i -P -n -sTCP:LISTEN | grep alpaca | awk '{print $9}' | xargs )\n"
			  log  "Info    -    Alpaca is running on TCP $(lsof -i -P -n -sTCP:LISTEN | grep alpaca | head -n 1 | awk '{print $9}' )\n"
		else 
			log  "Info - Alpaca does not appear to be running... Attempting to run it"
			brew services start alpaca > /dev/null 2>&1
			if [ $? -ne 0 ]; then
				handle_error "Error   - Brew failed to start the service, aborting... please troubleshoot as per https://github.com/samuong/alpaca"
			else
				if lsof -i -P -n -sTCP:LISTEN | grep alpaca > /dev/null 2>&1; then
					log  "Success - Brew set the Alpaca service to autostart (conceptually similar to managing services with launchd for autostart daemons on macOS)"
					log  "Info    - Alpaca is now running on TCP $(lsof -i -P -n -sTCP:LISTEN | grep alpaca | awk '{print $9}' | xargs )\n"
				fi
			fi
		fi
	fi
}

# Function to check PAC file setting for a specific interface
check_pac_file() {
  local interface=$1
  networksetup -getautoproxyurl $interface
}

# Function to attempt installing a package 3x times via Homebrew
attempt_install() {
    local package="$1"; local attempts=3
    while [ $attempts -gt 0 ]; do
        brew install "$package" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            log "Info    -   $package installed successfully."
            return 0
        fi
        log "Error   -   Failed to install $package. Attempts left: $attempts"
        log "Info    -   Let's try without proxy settings..."
        attempts=$((attempts - 1))
        unset {all,http,https}_proxy
    done
    handle_error "Error   - Failed to install $package after 3 attempts. Exiting..."
}

# Function to display the Help Menu
help() {
    clear
    log "Summary - The purpose of this script is to check network interfaces for PAC file settings, ensure Alpaca proxy\n\t\t\t      is installed and running if a PAC file is being used, and manage necessary proxy configurations."
    log "Author:  florian@photonsec.com.au\t\tgithub.com/Enelass"
    log "Runtime: currently running as $(whoami)"
    log "Usage: $@ [OPTION]..."
    log "  --help, -h\tDisplay this help menu..."
    log "  --version, -v\tDisplay $scriptname's version..."
    log "  --test, -t\tTest the connectivity only..."
    log "  --uninstall\tRemove the environment variables from Shell config file and remove Alpaca files and settings"
    log "  By default, if no switches are specified, it will run standone with verbose information"
    exit 0
}

##################################### Runtime ######################################


###########################   Script SWITCHES   ###########################
# Switches and Executions for the initial call (regardless of when)
while [[ $# -gt 0 ]]; do
  case $1 in
    --help|-h) help ;;
	--version|-v) log "Version - AlpacaSetup.sh $version"; exit 0 ;;
	--test|-t) test=1; connectivity_test ;;
    --uninstall|-u) uninst=1 ;;
   *) ;;
  esac
  shift
done

# If we want to uninstall, that'd be now...
if [[ test -eq 1 ]]; then
	connectivity_test
fi

# If we want to uninstall, that'd be now...
if [[ uninst -eq 1 ]]; then
	default_user > /dev/null 2>&1
	shell_config > /dev/null 2>&1
	uninstall
fi

# We list all interfaces and mark as active those with an private IP Address
# We then look for whether a PAC file, has or hasn't been set...
interfaces=$(networksetup -listallnetworkservices)
interfaces=$(sed 1d <<< "$interfaces")	# Ignore the first line (informational) of the output
UsePAC=false
log "Info    - Let's list our interfaces and look for a PAC File or URL..."
while IFS= read -r line; do
	IPAddr=$(networksetup -getinfo $line | grep -E '^IP address: ((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')
	if [[ -n $IPAddr ]]; then
    	log "Info         Active       :   $line  //  $IPAddr"
	else
		log "Info         Not Connected:   $line"
	fi
    pac_file_output=$(check_pac_file "$line")
    if [[ $pac_file_output == *"Enabled: Yes"* ]]; then
      UsePAC=true
      PACPath=$(echo "$pac_file_output" | grep URL)
    fi
done <<< "$interfaces"

if [[ $UsePAC ]]; then
	log "Info    - It appears we are using a PAC file..."
	log "Info        Proxy Address: "$PACPath""
	log "Info        We should use Alpaca then to make use of the PAC file via the various CLI...\n"
fi

# If we're using a PAC file, we'll need to have Alpaca running or we'll install it
install_alpaca

# Assuming we have a PAC File, Alpaca is installed and running as expected
# It's time to check if the proxy settings are well set and the connection can be established...
# Let's identify the logged in or default user and it's home directory...
default_user

# Let's identify the default Shell interpreter and associated config file for that user...
shell_config

# Let's inspect the file for existing environment variables & Let's reference this cacert.pem in the Shell Interpreter config file
shell_var
source "$CONFIG_FILE"; sleep 1

# Now that all requirements are met, we'll test the connectivity or revert the changes made by this script...
connectivity_test
