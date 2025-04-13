#!/bin/zsh
# Script to extract proxy addresses from PAC file and test connections
################################# Variables ########################################

local scriptname="$0"
# You can manually set your the PAC file URL if running this script in standalone mode.
# If invoked by other scripts, the PAC_FILE_URL will be overwritten by the one found in the system (interfaces or from cutill)...
PAC_FILE_URL="http://example.com/proxy.pac"
if [[ -n $pac_url ]]; then PAC_FILE_URL="$pac_url"; fi

pac_file="/tmp/proxy.pac"           # Temporary path to store the downloaded PAC file
testurl="https://www.google.com"    # URL for performing connectivity tests
timeout=3                           # cURL time out in seconds for testing proxies...


#################################  Functions ########################################
# Function to download the PAC file with retries
download_pac_file() {
    local retries=3; local attempt=0; local success=false
    while [[ $attempt -lt $retries ]]; do
        attempt=$((attempt + 1))
        logI "Downloading PAC file (Attempt $attempt of $retries) from $PAC_FILE_URL..."
        curl -lo "$pac_file" "$PAC_FILE_URL" >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            logS "  PAC file downloaded successfully in $pac_file\n"
            success=true
            break
        else
            logW "Failed to download PAC file. Retrying..."
        fi
    done

    if [[ $success == false ]]; then
        logE "Failed to download PAC file after $retries attempts. It was available earlier, so maybe your connection is down..."
    fi
}

# Function to test a given proxy
test_proxy_connection() {
    local proxy=$1
    local ip_port_regex='^((([a-zA-Z0-9](-?[a-zA-Z0-9])*\.?)*[a-zA-Z]{2,}|(([0-9]{1,3}\.){3}[0-9]{1,3}))(:(6553[0-5]|655[0-2][0-9]|65[0-4][0-9][0-9]|6[0-4][0-9][0-9][0-9]|[1-5][0-9]{4}|[0-9]{1,4})))$'
    if [[ $proxy =~ $ip_port_regex ]]; then
        # Clear line and display "Testing proxy"
        logI "Testing proxy $proxy..."

        # Perform the curl command through the proxy and capture the response code
        response=$(curl --max-time $timeout -kI -so /dev/null -x "$proxy" -w "%{http_code}" "$testurl")

        # Clear line and display the result
        if [[ "$response" == "000" ]]; then
            log "${RED}FAILURE${NC} - Proxy did not respond or requires authentication..."
            sleep 1; echo -en "\r\033[2K\033[F\033[2K\033[F\033[2K" # Clear the current line and two before
        elif [[ "$response" == "200" ]] || [[ "$response" == "301" ]] || [[ "$response" == "302" ]]; then
            logS "Proxy is working 👍"
            workingproxy="$proxy"       # Let's save this to instruct other scripts that a working proxy has been found
            sleep 4
        else
            log "${RED}FAILURE${NC} - Proxy returned unknown response code: $response"
            sleep 1; echo -en "\r\033[2K\033[F\033[2K\033[F\033[2K"
        fi
    fi
}


##################################### Runtime ######################################

echo; logI "  ---   ${PINK}SCRIPT: $scriptname${NC}   ---"
logI "        ${PINK}     This script is parse a PAC File and extract a working proxy address and port${NC}"

# Download the PAC file silently
download_pac_file

# Extract proxies and process each one using while read loop
if [[ -f $pac_file ]]; then
    logI "Extracting Proxy entries from the PAC file..."
    grep -Eo 'PROXY [^;"]+' "$pac_file" | sort | uniq | awk '{print $2}' |  while read -r proxy; do
        test_proxy_connection "$proxy"
        if [[ -n $workingproxy ]]; then break; fi # If we have a proxy, let's end the loop to save time...
    done
    if [[ -z ${workingproxy-} ]]; then # If we haven't found a proxy from the PAC, let's try again with a more permissive timeout, we really need a proxy...
        timeout=15
        grep -Eo 'PROXY [^;"]+' "$pac_file" | sort | uniq | awk '{print $2}' |  while read -r proxy; do
            test_proxy_connection "$proxy"
            if [[ -n $workingproxy ]]; then break; fi # If we have a proxy, let's end the loop to save time...
        done
    fi 
else
    logW "couldn't find the PAC file..."
fi