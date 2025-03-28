#!/bin/zsh
clear
# Extracting proxy address and PAC file

# Function to get HTTP proxy settings for a given network service
get_http_proxy_settings() {
    local service=$1
    local proxy_settings
    proxy_settings=$(networksetup -getwebproxy "${service}")

    # Extract server and port values
    local server
    local port
    server=$(echo "${proxy_settings}" | grep -E "^Server: " | awk '{print $2}')
    port=$(echo "${proxy_settings}" | grep -E "^Port: " | awk '{print $2}')

    # If enabled yes, look at it otherwise, discard...
    # Check if server and port are not empty or zero
    if [[ -n "${server}" && "${server}" != "0" && -n "${port}" && "${port}" != "0" ]]; then
        echo "HTTP Proxy settings for ${service}:"
        echo "${proxy_settings}"
        echo ""
    fi
}

get_proxy_settings() {
    local service=$1
    local proxy_settings
    echo "\n\nProxy settings for "$service""
    networksetup -getwebproxy "${service}"
    networksetup -getsecurewebproxy "${service}"
    networksetup -getsocksfirewallproxy "${service}"
    networksetup -getautoproxyurl "${service}"
}



# Fetch all network services, excluding the first line
interfaces=$(networksetup -listallnetworkservices | tail -n +2)


# Iterate over each network service and fetch HTTP proxy settings
while IFS= read -r service; do
    get_proxy_settings "${service}"
done <<< "$interfaces"





# Extracting proxy address from the PAC File
# URL to the PAC file
# We list all interfaces and mark as active those with an private IP Address
# We then look for whether a PAC file, has or hasn't been set...
# UsePAC=false
# log "Info    - Let's list our interfaces and look for a PAC File or URL..."
# while IFS= read -r line; do
# 	IPAddr=$(networksetup -getinfo $line | grep -E '^IP address: ((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')
# 	if [[ -n $IPAddr ]]; then
#     	log "Info         Active       :   $line  //  $IPAddr"
# 	else
# 		log "Info         Not Connected:   $line"
# 	fi
#     pac_file_output=$(check_pac_file "$line")
#     if [[ $pac_file_output == *"Enabled: Yes"* ]]; then
#       UsePAC=true
#       PACPath=$(echo "$pac_file_output" | grep URL)
#     fi
# done <<< "${interfaces}"


# if [[ -n $PACPath ]]; then
# 	# Download the PAC file
# 	curl -o proxy.pac "${PACPath}"

# 	# Function to extract proxy details from the PAC file
# 	extract_proxies_from_pac() {
# 	    local file=$1
# 	    echo "Extracting Proxy settings from PAC file:"
# 	    grep -Eo 'PROXY [^;"]+' "${file}" | sort | uniq
# 	}

# 	# Call the function to print proxies
# 	extract_proxies_from_pac "proxy.pac"
# fi