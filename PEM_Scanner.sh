#!/bin/zsh

#########################################################
# Written by Florian Bidabe / florian@photonsec.com.au
# DESCRIPTION: This script is designed to search for and
# enrich a list of PEM certificate authority
# files (cacert.pem) found in the MacOS System
# and User directories. It creates a CSV list
# of these files and performs integrity checks
# to verify their authenticity. The script also
# maintains a database of these files, allowing
# for easy tracking and comparison of changes
# INITIAL RELEASE DATE: 11-Mar-2025
# AUTHOR: Florian Bidabe
# LAST RELEASE DATE: 11-Mar-2025
# VERSION: 0.1
# REVISION: 0.1
#########################################################


# Condition to verify is teefile (the log file) is defined. If not, this script wasn't sourced/called/invoked by the main, so we'll abort
if [[ -z "${teefile-}" ]]; then 
    echo -e "WARNING - This script is not meant to be executed directly!\nIt will only run if invoked/sourced from proxy_cert_auto_setup.sh"
    exit 1
fi

# Function to search for PEM certificate authority on the MacOS System
enrich_list() {
	local cacertlist="$1" ; local cacertdb="$2" ; local exclude
	# Assuming $cacertlist contains multiple lines of code, we're removing empty lines
	cacertlist=$(echo "$cacertlist" | grep -v '^$')
	# Write CSV header and create (a new) Db
	echo "Application,File Path,Magic Byte,SHA1 Signature,LoggedIn User,Hostname,LastModified,Exclude" > "$cacertdb"
	# Process each line in the file
	while IFS= read -r file_path; do
	    if [ -f "$file_path" ]; then
	    	# This line attempts to identify to which application or library the cacert.pem file belongs to
			if [[ $file_path =~ "/Applications/(.*)/Contents/" ]]; then application_name="${match[1]}" && application_name="${application_name%.app}"; elif [[ $file_path =~ "/opt/homebrew/Cellar/([^/]+)(/([0-9.-]+))?/" ]]; then application_name="${match[1]}" && [[ -n ${match[3]} ]] && application_name+="/${match[3]}"; elif [[ $file_path =~ "/usr/local/([^/]+)/" ]]; then application_name="${match[1]}"; elif [[ $file_path =~ "pip" ]]; then application_name="pip"; elif [[ $file_path =~ "python([0-9.]+)?" ]]; then application_name="python${match[1]}"; elif [[ $file_path =~ "certifi" ]]; then application_name="certifi"; else application_name="Unknown"; fi
	        # This verifies that the cacert.pem is indeed a plain text file, if not these cacert.pem will be discared (and logged)
	        magic_byte=$(file -b --mime-type "$file_path")
	        # This capture the sha1 signature of the file, then strip the path, and only retain the digital signature
	        sha1_full=$(openssl sha1 "$file_path"); sha1=${sha1_full#*= } # $sha1_full includes the filename and sha1 signature, $sha1 only includes the signature
	        # We capture the timestamp of when the information for this line, so for this cacert.pem was captured.
	        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
	        # If filename isn't cacert.pem, exclude from patching, user can manually action oddly named files...
	        if [[ $file_path == *"cacert.pem"* ]]; then exclude=0; else exclude=1; fi
	        # Check these pem files truly are Root and signing CA (like a NGFW or proxy performing forward SSL inspection)
	        # It should ponly include CERTIFICATE, stricly no REQUEST indicative of a CSR, or PRIVATE KEY indicative of a certificate bundle
	        if [[ $magic_byte == "text/plain" ]] && grep -q 'BEGIN CERTIFICATE' $file_path && ! grep -q 'PRIVATE KEY' $file_path && ! grep -q 'CERTIFICATE REQUEST' $file_path; then
	        	logonly "Info    - Processing $file_path..."
	        	logonly "Info    -    The certificate is plain text and looks like a PEM CA, running more checks..."
	        	local cacount=$(grep "BEGIN CERTIFICATE" $file_path | wc -l | awk '{print $1}')
	        	if [[ $cacount -ge 10 ]]; then	# We're setting a minimum of 10 Root CAs to treat the file as a certificate store
	        		logonly "Info    -    This is a CA, it includes $cacount public (and possibly internal) Root CAs"
	        		logonly "Info    -    All checks are satisfactory, patching the PEM certificate store"
	        		# Adding the pem file location to the enriched CSV list of pem files to be patched
	        		echo "$application_name,$file_path,$magic_byte,$sha1,$logged_user,$(hostname),$timestamp,$exclude" >> "$cacertdb"
	        	else
	        	logonly "Info    -    Not a CA, it only contain $cacount Root CAs where a typical CA pem file (or certificate store) includes about ~130+ Root CAs"
	        	fi
	        fi
	    else
	    	logonly "Error   - File \""$file_path"\" doesn't exist..."
	    fi
	done < "$cacertlist"
}


# Create a list of pem files
if [ ! -d "$CDir" ]; then mkdir -p "$CDir"; fi

########################## Searching in System Context ##########################
log "Info    - Searching for PEM Certificate Stores (e.g. cacert.pem) in MacOS System..."
echo > "$cacert_syslist" # Reset System file...
log "Info    -     Searching in System context using \`locate\` (All disk but User directories)..."
if [[ -f $CDir/locate.enabled ]]; then
	log "Info    -     Good news, \`locatedb\` is initialised already! Scanning for new pem files in the system directories..."
	cd /; /usr/libexec/locate.updatedb 2>/dev/null # I didn't initially plan to rescan, but locate would only scan on a weekly basis otherwise... hence missing recently added pem files
else
	log "Info    -     Initialising \`locatedb\`, please wait..."; 
	cd /; /usr/libexec/locate.updatedb 2>/dev/null 
	echo > $CDir/locate.enabled; chflags hidden $CDir/locate.enabled
	log "Info    -     \`locatedb\` has finished indexing system files..."
fi
locate .pem | grep '/*.pem$' >> "$cacert_syslist"
sed -i '' '/^$/d' "$cacert_syslist" #Remove empty lines

# Maintain a System Db file with file signature / integrity checks
if [[ -f "$cacert_sysdb" ]]; then
	log "Info    -     A previous System certificate store database was found. Let's compare Db and look for new entries"
	mv "$cacert_sysdb" "$prevcacert_sysdb"	# Relabel "current Db" to "previous Db" (So "current Db" can be refreshed/re-created...) to compare the delta with previous one
else
	log "Info    -     No previous System certificate store database was found. Let's create a new one"
fi
enrich_list	"$cacert_syslist" "$cacert_sysdb"			# Create a new System Db from CSV List 
log "Info    - The system CA pem files are listed in $cacert_syslist and $cacert_sysdb"


########################### Scanning in User context ###########################
log "Info    - Searching for PEM Certificate Stores (cacert.pem) in MacOS System and User Context..."
log "Info    -     locatedb cannot index user files (security risk) unless we disable SIP Integrity Check. We'll use GNU \`find\` instead..."
echo > "$cacert_userlist" # Reset file for the listing of PEM certificate stores in user directories...
log "Info    -     Searching in User context only using \`GNU Find\`..."
if [ "$EUID" -ne 0 ]; then # If unpriviledged, let's scan the current user directory only since the user won't be permitted to scan other user directories
	log "Info    -     Scanning logged-in user directory in /Users/$logged_user... this will take a while..."
	if [[ -d /Users/$logged_user ]]; then
		find /Users/$logged_user -name "*.pem" 2>/dev/null >> "$cacert_userlist"
	else log "Error    -     Couldn't find the user directory, exiting..."
	fi
else # let's target all users... 
	log "Info    -     Scanning all user directories in /Users... this will take a while..."
	find /Users -name "*.pem" 2>/dev/null >> "$cacert_userlist"
fi

# Maintain a User Db file with file signature / integrity checks
if [[ -f "$cacert_userdb" ]]; then
	log "Info    -     A previous User certificate store database was found. Let's compare Db and look for new entries"
	mv "$cacert_userdb" "$prevcacert_userdb" # Relabel "current Db" to "previous Db" (So "current Db" can be refreshed/re-created...) and to compare the delta with previous one
else
	log "Info    -     No previous User certificate store database was found. Let's create a new one"
fi
enrich_list	"$cacert_userlist" "$cacert_userdb"			 # Create a new User Db from CSV List 
log "Info    - The user certificate stores were listed in $cacert_userlist and $cacert_userdb"

if [[ -f "$cacertdb" ]]; then mv $cacertdb $prevcacertdb; fi
# Concatenating both the system Db (if any) and user Db
if [[ -f "$cacert_sysdb" ]]; then
	cat "$cacert_sysdb" <(tail -n +2 "$cacert_userdb") > "$cacertdb"
else
	cp "$cacert_userdb" > "$cacertdb"
fi

# Silently clean up DB tmp files to only keep the consolidated and enriched list of PEM certificate stores
cd "$CDir"; cat "$cacert_userlist" > pemlist.txt; cat "$cacert_syslist" >> pemlist.txt; # Create a list of all pem files found
rm $cacert_sysdb $cacert_userdb $cacert_userlist $cacert_syslist $prevcacert_sysdb $prevcacert_userdb >/dev/null 2>&1 # Clean-up temp files, keep consolidated Db and pemlist