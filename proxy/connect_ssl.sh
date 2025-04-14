#!/bin/zsh
local scriptname="$0"
local current_dir=$(dirname $(realpath $0))
if [[ -z $teefile ]]; then clear; source "$current_dir/../stderr_stdout_syntax.sh"; fi

################################ VARIABLES #############################
website_regex="^https:\/\/([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}\/?$"
websites=("https://photonsec.com.au" "https://www.google.com")  # List of websites to check for check_website()
    # Read additional websites from the configuration file
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and lines starting with "#"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ $website_regex ]]; then websites+=("$line"); fi
    done < "$current_dir/websites.config"


local curltimeout=5         # Number of seconds after which cURL will give up establishing a connection
local ssl_success_count=0   # Counter for successful web connections for check_website_withSSL()
local max_success=5         # Maximum number of successful web connections
variables=("GIT_SSL_CAINFO" "CURL_CA_BUNDLE" "REQUESTS_CA_BUNDLE" "AWS_CA_BUNDLE" "NODE_EXTRA_CA_CERTS" "SSL_CERT_FILE")

################################ FUNCTIONS #############################

# Function to verify if HTTPS requests via the proxy do succeed...
check_website_withSSL() {
    url=$1
    local issuer
    logI "  Checking connection to ${GREENW}$url${NC} (${ORANGE}with${NC} SSL verification)"
    start_spinner "Please wait..."
    output=$(curl -svI --connect-timeout $curltimeout --max-time $curltimeout "$url" 2>&1)
    stop_spinner
    if [ $? -eq 0 ]; then
        # If we can connect, extract the issuer...
        issuer=$(echo $output | grep "issuer:" | sed -n 's/.*CN=\([^;]*\).*/\1/p')
        issuers+="$issuer;"
        echo -en "\r\033[2K\033[F\033[2K"
        logS "    Connection to $url succeeded, Certificate issuer is: ${BLUEW}$issuer${NC}"
        # Let's attempt to see if this is public or private issuer
        # logI "    The issuer was trusted either because it is a publibly signed, or it is internally signed with a Internal Root CA trusted by MacOS Keychain..."
        # logI "       cURL used to test connectity, ALWAYS uses MacOS internal trusted certificates"
        # logI "       (even if specifying a certifice store without Internal Root CAs with the ${GREENW}--cacert${NC} switch."
        # logI "       Since a lot of CLI and a few GUIs program does not rely on the MacOS trusted certificates in Keychain Access,"
        # logI "       we need to provide a custom Certificate authority file (cacert.pem)"
        ((ssl_success_count++))
    else
        output=$(curl -vIk "$url" 2>&1)
        if [ $? -eq 0 ]; then
            issuer=$(echo "$output" | grep "issuer:" | sed -n 's/.*CN=\([^;]*\).*/\1/p')
            echo -en "\r\033[2K\033[F\033[2K"
            logW "    Connection to $url failed. Certificate issuer is not trusted: ${BLUEW}$issuer${NC}"
        else
            echo -en "\r\033[2K\033[F\033[2K"
            logW "    Connection to $url failed. It could not be established..."
        fi
        if echo "$output" | grep "self signed certificate" > /dev/null 2>&1; then ((trustissue_cnt++)); fi # If the certificate is signed by a trusted issuer but is expired or has insecure ciphers refused by the server, this variable will not be set...
    fi
}

################################ RUNTIME #############################

# Let's start clean with unsetting all current Env variable for SSL Certificate Store
for var in "${variables[@]}"; do unset "$var"; done # Loop through the array and unset custom Certificate Store variable for various clients

# Execute the function to check web connectivity without SSL verification
echo; logI "  ---   ${PINK}SCRIPT: $scriptname${NC}   ---"
logI "        ${PINK}     This script is intended to check whether HTTPS requests are intercepted or not...${NC}"

# If we couldn't establish web connections, let's stop there since we have either proxy or internet connectivity issues...
logI "We will now check if the web requests/responses are SSL intercepted!"
logI "The issuer for each certificate website will be displayed and captured"
for site in "${websites[@]}"; do
  check_website_withSSL "$site"
done

if [[ $trustissue_cnt -gt 0 ]]; then
    echo ""; logW "We couldn't connect some websites while verifiying SSL certificates"
    logW "See cURL Error message below..."
    curl --head "$url" 2>&1 | tail -n +4 | grep -v "Established"
    logI "    We need to download Custom certificate Store (PEM file) and add internal signing Root CAs"
    logI "    then create persistent environment variables pointing to this custom Certificate Store..."
    source "$current_dir/../SSL/PEM_Var.sh"
fi

if [[ $ssl_success_count -gt $max_success ]]; then
    ssl_issuers=()
    while IFS= read -r issuer; do
        # Append each issuer to the array
        ssl_issuers+=("$issuer")
    done < <(echo "$issuers" | tr ';' '\n' | sort -u | grep -v '^$')
    for issuer in "${ssl_issuers[@]}"; do
        if cat /etc/ssl/cert.pem | grep $issuer; then # We're lucky this list contains metadata, otherwise we'd have to use openssl to displau each issuer from the Base64...
            logI "We have found the following ${GREENW}public${NC} issuer: $issuer"
            PublicCAOnly=true
        else
            source "$current_dir/../SSL/Keychain_InternalCAs.sh" --silent  #Retrieves a list of Internal Root and Intermediate CAs silently
            if echo $CAList | grep -q $issuer; then
                logS "The certificate issuer $issuer is ${GREENW}internal${NC}"
                NeedCustomCacert=true
            else
                logW "The certificate issuer $issuer is not public nor internal..."
            fi
        fi
    done

    if [[ -n $NeedCustomCacert ]]; then
        logI "We have found website(s) signed by internal certificate authority(ies)"
        logI "    We need to create a Custom certificate Store (PEM file) and add our internal signing Root CAs"
        logI "    then we'll create persistent environment variables pointing to this custom Certificate Store to solve of SSL trust issues..."
        source "$current_dir/../SSL/PEM_Var.sh"
    fi
    if [[ -z ${NeedCustomCacert-} && -n $PublicCAOnly ]]; then
        logI "All websites were signed by Public CAs and not internal ones..."
        logW "We won't therefore create a customer Certificate Store including internal CAs nor reference it in your Shell config file..."
        logI "If you want to create a custom Certificate Authority Store containing public and internal CAs,"
        logI "   please add SSL inspected websites to $(realpath ./websites.config) and run this script again, or"
        logI "   you could also run $(realpath ../SSL/PEM_Var.sh)"
        logI "   or ${GREENW}$(realpath ../proxy_ssl_trust.sh) --var${NC}"
    fi
fi