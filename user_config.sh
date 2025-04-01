#!/bin/zsh

if [[ -z ${logI-} ]]; then source ./stderr_stdout_syntax.sh; fi

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
	else logS "    Home directory for "$logged_user" is located at "$HOME_DIR""
	fi
}

default_user; shell_config