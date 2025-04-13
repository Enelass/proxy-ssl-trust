#!/bin/zsh
local scriptname="$0"
local current_dir=$(dirname $(realpath $0))
if [[ -z ${logI-} ]]; then source "$current_dir/../stderr_stdout_syntax.sh"; fi


###################################### FUNCTIONS ##########################################

# Function to get and process HTTP proxy settings for a given network service
get_proxy_settings() {
    local service=$1; local webproxy_settings securewebproxy_settings autoproxy_settings
    logI "    Proxy settings for $service"
    # Fetch web proxy settings
    webproxy_settings=$(networksetup -getwebproxy "${service}")
    if echo "$webproxy_settings" | grep -q "Enabled: Yes"; then
        logI "    getwebproxy $webproxy_settings" | grep -v "Enabled"
    else unset webproxy_settings
    fi

    # Fetch secure web proxy settings
    securewebproxy_settings=$(networksetup -getsecurewebproxy "${service}")
    if echo "$securewebproxy_settings" | grep -q "Enabled: Yes"; then
        logI "getsecurewebproxy $securewebproxy_settings" | grep -v "Enabled"
    else unset securewebproxy_settings
    fi

    # Fetch auto proxy settings
    autoproxy_settings=$(networksetup -getautoproxyurl "${service}")
    if echo "$autoproxy_settings" | grep -q "Enabled: Yes"; then
        pac_urls+=($(echo "$autoproxy_settings" | grep -E "^URL: " | awk '{print $2}'))
        logI "     getautoproxy $autoproxy_settings" | grep "URL: "
    else unset autoproxy_settings
    fi

    if [[ -z "${webproxy_settings-}" && -z "${securewebproxy_settings-}" && -z "${autoproxy_settings-}"  ]]; then
        logI "    No Pac file URL found for $service"
    fi
}

###################################### RUNTIME ##########################################
echo; logI "  ---   ${PINK}SCRIPT: $scriptname${NC}   ---"
logI "        ${PINK}     This script is intended to verify network connectivity and whether a PAC file can be found${NC}"

# Fetch all network services, excluding the first line
interfaces=$(networksetup -listallnetworkservices | tail -n +2)

# Iterate over each network service and fetch HTTP proxy settings
while IFS= read -r service; do
    IPAddr=$(networksetup -getinfo "$service" | grep -E '^IP address: ((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')
    if [[ -n $IPAddr ]]; then
        logS  "   $service is active  //  $IPAddr"
        activeIP=true
        get_proxy_settings "${service}"
    else
        logW "   $service is inactive, it doesn't have an IP address or a valid one..."
        get_proxy_settings "${service}"
        sleep 2; echo -en "\r\033[2K\033[F\033[2K\033[F\033[2K\033[F\033[2K"
    fi
    
done <<< "$interfaces"

if [[ -z ${activeIP-} ]]; then
    logE "There are no interfaces with a valid IP address, you're either disconnected or with a APIPA issue... Aborting!"
else
    # Fetch scutil proxy settings as well...
    scutil_proxy_info=$(scutil --proxy)
    scutil_proxy_url=$(echo "$scutil_proxy_info" | grep 'ProxyAutoConfigURLString' | awk '{print $3}')
    echo ""; logI "Looking for proxy PAC (Proxy Auto-Configuration) File from \`scutil --proxy\` ..."
    if [[ -n "$scutil_proxy_url" ]]; then
        pac_urls+=("$scutil_proxy_url")
        logI "Pac file URL found: $scutil_proxy_url"
    else logI "No Pac file URL found from scutil command..."
    fi
fi

# Check if any proxy URL was found
if [[ ${#pac_urls[@]} -eq 0 ]]; then
    logW "PAC file URL could not be found"
else
    # Remove duplicate URLs and then display unique URLs
    proxy_urls=($(echo "${pac_urls[@]}" | tr ' ' '\n' | sort -u))
    echo ""; logI "PAC file URL(s):"
    # Test each PAC URL to check if the file exists
    for url in "${proxy_urls[@]}"; do
        if curl --head --silent --fail "$url" > /dev/null; then
            logS "Testing PAC file URL: $url... It can be downloaded!"
            pac_url="$url"      # We set this variable for the other script to know we have a pac file
        else
            logW "Testing PAC file URL: $url... It cannot be read!"
            #sleep 2; echo -en "\r\033[2K\033[F\033[2K"
        fi
    done
fi