#!/bin/zsh

#########################################################
# Written by Florian Bidabe / florian@photonsec.com.au
# DESCRIPTION: This script is designed to search for and
# enrich a list of PEM certificate authority
# files (pem file(s)) found in the MacOS System
# and User directories. It creates a CSV list
# of these files and performs integrity checks
# to verify their authenticity. The script also
# maintains a database of these files, allowing
# for easy tracking and comparison of changes
# INITIAL RELEASE DATE: 11-Mar-2025
# AUTHOR: Florian Bidabe
# LAST RELEASE DATE: 04-Apr-2025
# VERSION: 0.1
# REVISION: 0.4
#########################################################



# Condition to verify is teefile (the log file) is defined. If not, this script wasn't sourced/called/invoked by the main, so we'll set a few vars
script_name="$0"
script_dir=$(dirname $(realpath $0))
if [[ -z ${logI-} ]]; then
	clear
	AppName="PEM_Scanner"
	teefile="/tmp/$AppName.log"
	source "$script_dir/stderr_stdout_syntax.sh"
fi
if [[ -z "${HOME_DIR-}" ]]; then source "$script_dir/user_config.sh" --quiet; fi

################################## Variables ###################################
CDir="$HOME_DIR/Applications/proxy_ssl_trust/scan"		# Where these files will be stored
pem_syslist="$CDir/pem_syslist.csv"						# A new generated list of pem file(s) files found in the system context
pem_userlist="$CDir/pem_userlist.csv"					# A new generated list of pem file(s) files found in the user context
pem_sysdb="$CDir/pem_sysdb.csv" 							# The system Db file (with metadata)
pem_userdb="$CDir/pem_userdb.csv" 						# The user Db file (with metadata)
pemdb="$CDir/pemdb.csv" 											# The Final Db file (with metadata), combining user and system files
prevpem_sysdb="$CDir/pem_sysdb.backup.csv"		# The previous System Db File we use to compare against current to skip patched pem file(s)
prevpem_userdb="$CDir/pem_userdb.backup.csv"	# The previous user Db File we use to compare against current to skip patched pem file(s)
prevpemdb="$CDir/pemdb.backup.csv"						# The previous Db File we use to compare against current to skip patched pem file(s)


################################## Functions ###################################

# Help function to display usage guide and available options
help() {
  cat << EOF
Usage: $script_name [OPTIONS]

This script searches and enriches a list of PEM certificate authority files found in the MacOS System
and User directories. It creates a CSV list of these files and performs integrity checks to verify their authenticity.
The script also maintains a database of these files, allowing for easy tracking and comparison of changes.

Options:
  --system        Search for PEM Certificate Stores in the System context excluding User directories.
  --user          Search for PEM Certificate Stores in the User context.
  --quick         Perform a quick scan (avoiding a full rescan of the system).
  --verbose       Enable verbose logging and open the log file with detailed information.
  --uninstall     Remove all files created by the script in the specified directory.
  --help          Display this help message and exit.

Examples:
  
  $script_name --quick
    Search for PEM files in the current User directory and system and generate a CSV list.

  sudo $script_name --user
    Search for PEM files in all Users directories and generate a CSV list.

  sudo $script_name --system
    Search for PEM files in the MacOS System directory and generate a CSV list.

  sudo $script_name --quick --system
    Perform a quick search for PEM files in the System context without forcing a full rescan.

  sudo $script_name --uninstall
    Uninstall and remove all files created by the script.

Author:
  Florian Bidabe (florian@photonsec.com.au)
  Initial Release Date: 11-Mar-2025
  Last Release Date: 04-Apr-2025
  Version: 0.1
  Revision: 0.4

EOF
}


# Function to search for PEM files (CLI certificate store) on the MacOS filesystem
enrich_list() {
	local pemlist="$1" ; local pemdb="$2" ; local exclude
	# Assuming $pemlist contains multiple lines of code, we're removing empty lines
	pemlist=$(echo "$pemlist" | grep -v '^$')
	# Write CSV header and create (a new) Db
	echo "Application,File Path,Magic Byte,SHA1 Signature,LoggedIn User,Hostname,LastModified,Exclude" > "$pemdb"
	# Process each line in the file
	while IFS= read -r file_path; do
	    if [[ $(realpath "$file_path") == "$file_path" ]]; then
		    if [[ -f "$file_path" ]]; then
		    	# This line attempts to identify to which application or library the pem file(s) file belongs to
				if [[ $file_path =~ "/Applications/(.*)/Contents/" ]]; then application_name="${match[1]}" && application_name="${application_name%.app}"; elif [[ $file_path =~ "/opt/homebrew/Cellar/([^/]+)(/([0-9.-]+))?/" ]]; then application_name="${match[1]}" && [[ -n ${match[3]} ]] && application_name+="/${match[3]}"; elif [[ $file_path =~ "/usr/local/([^/]+)/" ]]; then application_name="${match[1]}"; elif [[ $file_path =~ "pip" ]]; then application_name="pip"; elif [[ $file_path =~ "python([0-9.]+)?" ]]; then application_name="python${match[1]}"; elif [[ $file_path =~ "certifi" ]]; then application_name="certifi"; else application_name="Unknown"; fi
		        # This verifies that the pem file(s) is indeed a plain text file, if not these pem file(s) will be discared (and logged)
		        magic_byte=$(file -b --mime-type "$file_path")
		        # This capture the sha1 signature of the file, then strip the path, and only retain the digital signature
		        sha1_full=$(openssl sha1 "$file_path"); sha1=${sha1_full#*= } # $sha1_full includes the filename and sha1 signature, $sha1 only includes the signature
		        # We capture the timestamp of when the information for this line, so for this pem file(s) was captured.
		        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
		        # If filename isn't pem file(s), exclude from patching, user can manually action oddly named files...
		        # if [[ $file_path == *"pem file(s)"* ]]; then exclude=0; else exclude=1; fi
		        exclude=1 # Mark all files for patching exclusion, the user, will need to manually mark it as 0 in the CSV to patch that pem file using --patch
		        # Check these pem files truly are Root and signing CA (like a NGFW or proxy performing forward SSL inspection)
		        # It should only include CERTIFICATE, stricly no REQUEST indicative of a CSR, or PRIVATE KEY indicative of a certificate bundle
		        if [[ $magic_byte == "text/plain" ]] && grep -q 'BEGIN CERTIFICATE' $file_path && ! grep -q 'PRIVATE KEY' $file_path && ! grep -q 'CERTIFICATE REQUEST' $file_path; then
		        	logonly "Info    - Processing $file_path..."
		        	logonly "Info    -    The certificate is plain text and looks like a PEM CA, running more checks..."
		        	local cacount=$(grep "BEGIN CERTIFICATE" $file_path | wc -l | awk '{print $1}')
		        	if [[ $cacount -ge 10 ]]; then	# We're setting a minimum of 10 Root CAs to treat the file as a certificate store
		        		logonly "Info    -    This is a CA, it includes $cacount public (and possibly internal) Root CAs"
		        		logonly "Info    -    All checks are satisfactory, patching the PEM certificate store"
		        		# Adding the pem file location to the enriched CSV list of pem files to be patched
		        		echo "$application_name,$file_path,$magic_byte,$sha1,$logged_user,$(hostname),$timestamp,$exclude" >> "$pemdb"
		        	else
		        		logonly "Info    -    Not a CA, it only contain $cacount Root CAs where a typical CA pem file (or certificate store) includes about ~130+ Root CAs"
		        	fi
		        fi
		    else
		    	logonly "Error   - File \""$file_path"\" doesn't exist..."
		    fi
		else
			logonly "Info    - $file_path is a symbolic link to $(realpath "$file_path"), skipping entry to avoid duplicates..."
		fi
	done < "$pemlist"
}

# Function to search PEM Sertificate Stores in the System using locate
system() {
	if [[ "$EUID" -ne 0 && -z $quick ]]; then
		logW "User elevation is required to scan the system"
		logW "If you wish to scan only the current user, please run ${GREENW}sudo $script_name${NC}...\n"
		help
		exit 1
	fi
	logI "Searching for PEM Certificate Stores (e.g. pem file(s)) in MacOS ${BLUEW}System-Wide${NC} excluding User directories..."
	echo > "$pem_syslist" # Reset System file...
	logI "    Searching in System context using \`locate\` (All disk but User directories)..."
	if [[ -f $CDir/locate.enabled ]]; then
		logI "    Good news, \`locatedb\` is initialised already!"
		cd /
		if [[ ${quick} -eq 1 ]]; then
			logI "    ${BLUEW}--quick${NC} switch was selected... we will not force a rescan (${GREENW}locate${NC} scan the system on a weekly basis anyway...)"
		else
			logI "    Scanning for new pem files in the system directories. Please wait..."
			/usr/libexec/locate.updatedb 2>/dev/null
			logI "    \`locatedb\` has finished indexing system files..."
		fi
	else
		logI "    Initialising \`locatedb\`, please wait..."; cd /
		if [[ "$EUID" -ne 0 ]]; then logW "It looks like locate.updatedb was never initialised so using it might fail... to initialise it, run $script_name as root/sudo"; fi
		/usr/libexec/locate.updatedb 2>/dev/null 
		echo > $CDir/locate.enabled; chflags hidden $CDir/locate.enabled
		logI "    \`locatedb\` has finished indexing system files..."
	fi
	locate .pem | grep '/*.pem$' >> "$pem_syslist"
	sed -i '' '/^$/d' "$pem_syslist" #Remove empty lines

	# Maintain a System Db file with file signature / integrity checks
	if [[ -f "$pem_sysdb" ]]; then
		logI "    A previous System certificate store database was found. Let's compare Db and look for new entries"
		mv "$pem_sysdb" "$prevpem_sysdb"	# Relabel "current Db" to "previous Db" (So "current Db" can be refreshed/re-created...) to compare the delta with previous one
	else
		logI "    No previous System certificate store database was found. Let's create a new one"
	fi
	sed -i '' '/^$/d' "$pem_syslist"				# Remove empty lines
	enrich_list	"$pem_syslist" "$pem_sysdb"			# Create a new System Db from CSV List 
	logS "    System PEM files were successfully processed!"
	logI "    Files are listed in ${GREENW}$CDir/cache${NC}"
}

user_context() {
	if [[ "$EUID" -ne 0 && -z $quick ]]; then
		logW "User elevation is required to scan all user directoties"
		logW "If you wish to scan only the current user, please run ${GREENW}$script_name --quick --user${NC}\n"
		help
		exit 1
	fi

	logI "Searching for PEM Certificate Stores (pem files) in MacOS ${BLUEW}User Context${NC}..."
	logI "    locatedb cannot index user files (security risk) unless we disable SIP Integrity Check. We'll use GNU \`find\` instead..."
	echo > "$pem_userlist" # Reset file for the listing of PEM certificate stores in user directories...
	logI "    Searching in User context only using \`GNU Find\`..."
	if [[ -n ${quick-} ]]; then
		logI "    Scanning logged-in user directory in /Users/$logged_user... this will take a while..."
		if [[ -d /Users/$logged_user ]]; then
			find /Users/$logged_user -name "*.pem" 2>/dev/null >> "$pem_userlist"
		else logW "    Couldn't find the user directory..."
		fi
	else # let's target all users unless --quick was selected... 
			logI "    Scanning all user directories in /Users... this will take a while..."
			find /Users -name "*.pem" 2>/dev/null >> "$pem_userlist"
	fi


	# Maintain a User Db file with file signature / integrity checks
	if [[ -f "$pem_userdb" ]]; then
		logI "    A previous User certificate store database was found. Let's compare Db and look for new entries"
		mv "$pem_userdb" "$prevpem_userdb" # Relabel "current Db" to "previous Db" (So "current Db" can be refreshed/re-created...) and to compare the delta with previous one
	else
		logI "    No previous User certificate store database was found. Let's create a new one"
	fi
	sed -i '' '/^$/d' "$pem_userlist"					 # Remove empty lines
	enrich_list	"$pem_userlist" "$pem_userdb"			 # Create a new User Db from CSV List 
	logS "    The user certificate stores were sucessfully processed!"
	logI "    Files are listed in ${GREENW}$CDir/cache${NC}"
}


# Function to delete all generated files
uninstall() {
	logI "    User requested to ${BLUEW}--scan_uninstall${NC}. Removing all files created by the --scan option. Please wait..."
	rm -R -f "$CDir" >/dev/null 2>&1
	if [[ ! -d $CDir ]] ; then
		logI "    All files were successfully removed..."; exit 0
	else
		logE "    We could not delete all files and directory in $CDir... Aborting"
	fi
}

# Function to consolidate and clean-up all files
file-cleanup() {
	#Keep previous Db for comparison
	if [[ -f "$pemdb" ]]; then mv $pemdb $prevpemdb; fi

		# Concatenating both the system Db (if any) and user Db
	if [[ -f "$pem_sysdb" && -f "$pem_userdb" ]]; then
		cat "$pem_sysdb" <(tail -n +2 "$pem_userdb") > "$pemdb"
	fi
	if [[ -f "$pem_sysdb" && ! -f "$pem_userdb" ]]; then
		cp "$pem_sysdb" > "$pemdb"
	fi
	if [[ ! -f "$pem_sysdb" && -f "$pem_userdb" ]]; then
		cp "$pem_userdb" > "$pemdb"
	fi

	# Create a list of all pem files found
	cd "$CDir";
	if [[ -f "$pem_userlist" && ! -f "$pem_syslist" ]]; then cat "$pem_userlist" > pemlist.txt; fi 
	if [[ -f "$pem_syslist" && ! -f "$pem_userlist" ]]; then cat "$pem_syslist" > pemlist.txt; fi
	if [[ -f "$pem_syslist" && -f "$pem_userlist" ]]; then
		cat "$pem_userlist" > pemlist.txt
		cat "$pem_syslist" >> pemlist.txt
	fi

	# Move secondary files to  
	if [ ! -d "$CDir/cache" ]; then mkdir -p "$CDir/cache"; fi
	if [[ -f "$pem_userlist" ]]; then mv "$pem_userlist" "$CDir/cache"; fi 
	if [[ -f "$pem_syslist" ]]; then mv "$pem_syslist" "$CDir/cache"; fi 
	if [[ -f "$pem_userdb" ]]; then mv "$pem_userdb" "$CDir/cache"; fi 
	if [[ -f "$pem_sysdb" ]]; then mv "$pem_sysdb" "$CDir/cache"; fi 

	# Silently clean up DB tmp files to only keep the consolidated and enriched list of PEM certificate stores
	# rm $pem_sysdb $pem_userdb $pem_userlist $pem_syslist $prevpem_sysdb $prevpem_userdb >/dev/null 2>&1 # Clean-up temp files, keep only consolidated Db and pemlist

	# If this script ran elevated, we need to allow the users to edit or dispose of the files...
	# E.g. the user might want to change some Exclude flags to 0, so be able to ./PEM_patch them...
	if [[ "$EUID" -eq 0 ]]; then
		chown -R  "$logged_user" "$(dirname "$CDir")"
		chmod -R 755  "$(dirname "$CDir")"
	fi
}

################################## Runtime #####################################
###########################   Script SWITCHES   ###########################
# Switches and Executions for the initial call (regardless of when)
while [[ $# -gt 0 ]]; do
  case $1 in
  --uninstall) uninstall ;;
	--system) system_only=1 ;;
	--user) user_only=1;;
	--quick) quick=1 ;;
	--verbose) verbose=1 ;;
	--help) help ; exit 0 ;;
   *) ;;
  esac
  shift
done

if [[ "$EUID" -ne 0 && -z $quick ]]; then
	logW "User elevation is required. Please run again as root or sudo\n"
	help
	exit 1
fi

# Create directory it it doesn't exists...
if [ ! -d "$CDir" ]; then mkdir -p "$CDir"; fi

# Searching in System Context
if [[ -z ${user_only-} ]]; then system; fi 

# Scanning in User context
if [[ -z ${system_only-} ]]; then user_context; fi

# File cleanup
file-cleanup

# Last checks
if [[ ! -f "$pemdb" ]]; then
	logW "Certificate Stores database (${GREENW}$pemdb${NC}) could not be found..."
	logE "Scanning has failed, please check the logs in $teefile"
fi

open "$(dirname "$pemdb")"
if [[ ${verbose} -eq 1 ]]; then
	logI "${BLUEW}--verbose${NC} was requested, we'll open the log file for full details..."
	open "$teefile"
fi