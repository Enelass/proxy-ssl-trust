#!/bin/zsh
# Script to extract proxy addresses from PAC file and test connections
clear

# URL of the PAC file
PAC_FILE_URL="http://pac.internal.cba/cba.pac"
# Temporary path to store the downloaded PAC file
pac_file="/tmp/proxy.pac"
# URL for performing connectivity tests
testurl="https://www.google.com"
# cURL time out in seconds for testing proxies...
timeout=2

# ANSI color codes for stdout status code
RED='\033[1;31m'
GREEN='\033[1;32m'
GREENW='\033[0;32;47m'
BLUEW='\033[0;34;47m'
NC='\033[0m' # No Color

######################## A bit of epic music never hurts ##########################
source ./play.sh

# Function to download the PAC file with retries
download_pac_file() {
    local retries=3; local attempt=0; local success=false
    while [[ $attempt -lt $retries ]]; do
        attempt=$((attempt + 1))
        echo "Downloading PAC file (Attempt $attempt of $retries) from $PAC_FILE_URL..."
        curl -o "$pac_file" "$PAC_FILE_URL" >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            echo "PAC file downloaded successfully in $pac_file\n"
            success=true
            break
        else
            echo "Failed to download PAC file. Retrying..."
        fi
    done

    if [[ $success == false ]]; then
        echo "Failed to download PAC file after $retries attempts."
        exit 1
    fi
}

# Function to extract proxy settings from the PAC file and store them in a variable
extract_proxies_from_pac() {

}

# Function to test a given proxy
test_proxy_connection() {
    local proxy=$1
    local ip_port_regex='^((([a-zA-Z0-9](-?[a-zA-Z0-9])*\.?)*[a-zA-Z]{2,}|(([0-9]{1,3}\.){3}[0-9]{1,3}))(:(6553[0-5]|655[0-2][0-9]|65[0-4][0-9][0-9]|6[0-4][0-9][0-9][0-9]|[1-5][0-9]{4}|[0-9]{1,4})))$'
    if [[ $proxy =~ $ip_port_regex ]]; then
        # Clear line and display "Testing proxy"
        echo -en "\r\033[2KTesting proxy $proxy..."

        # Perform the curl command through the proxy and capture the response code
        response=$(curl --max-time $timeout -kI -so /dev/null -x "$proxy" -w "%{http_code}" "$testurl")

        # Clear line and display the result
        echo -en "\r\033[2K"
        if [[ "$response" == "000" ]]; then
            echo -en "${RED}FAILURE${NC} - Proxy $proxy did not respond or requires authentication..."
            sleep 1
            echo -en "\r\033[2K"
        elif [[ "$response" == "200" ]] || [[ "$response" == "301" ]] || [[ "$response" == "302" ]]; then
            echo -e "${GREEN}SUCCESS${NC} - Proxy $proxy is working 👍"
        else
            echo -en "${RED}FAILURE${NC} - Proxy $proxy returned unknown response code: $response"
            sleep 1
            echo -en "\r\033[2K"
        fi
    fi
}


# Download the PAC file silently
download_pac_file

# Extract proxies and process each one using while read loop
if [[ -f $pac_file ]]; then
    echo -e "Extracting Proxy entries from the PAC file...\n"
    grep -Eo 'PROXY [^;"]+' "$pac_file" | sort | uniq | awk '{print $2}' |  while read -r proxy; do
    test_proxy_connection "$proxy"
    done
else echo "couldn't find the PAC file..."
fi
