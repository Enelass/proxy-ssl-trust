#!/bin/zsh

if [[ -z ${logI-} ]]; then source ./stderr_stdout_syntax.sh; afplay ./Two_Swords.m4a & ; clear; fi


################################ VARIABLES #############################
website_regex="^(https?:\/\/)?([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}\/?$"
websites=("https://photonsec.com.au" "https://www.google.com")  # List of websites to check for check_website()
    # Read additional websites from the configuration file
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and lines starting with "#"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ $website_regex ]]; then websites+=("$line"); fi
    done < websites.config

max_success=1   # Maximum number of successful web connections to stop after webconn_checks()
success_count=0 # Counter for successful web connections for check_website_withoutSSL()
success_cnt=0   # Counter for successful web connections for check_website_withSSL()
variables=("GIT_SSL_CAINFO" "CURL_CA_BUNDLE" "REQUESTS_CA_BUNDLE" "AWS_CA_BUNDLE" "NODE_EXTRA_CA_CERTS" "SSL_CERT_FILE")

################################ FUNCTIONS #############################

# Function to check if a website is reachable over HTTPS without checking the certificate
check_website_withoutSSL() {
    url=$1
    logI "  Checking connection to $url (without SSL verification). Please wait..."
    if curl -skI "$url" | grep -E "HTTP/2 200|HTTP/1.1 200" > /dev/null; then
        logS "    Connection succeeded: ${GREENW}$url${NC}"
        ((success_count++))
    else
        logW "    Connection failed: ${GREENW}$url${NC}"
        sleep 2; echo -en "\r\033[2K\033[F\033[2K\033[F\033[2K"
    fi
    
}

check_website_withSSL() {
    url=$1
    local issuer
    output=$(curl --head --verbose "$url" 2>&1)
    echo -en "\r\033[2K\033[F\033[2K\033[F\033[2K"
    if [ $? -eq 0 ]; then
        # If we can connect, extract the issuer...
        issuer=$(echo $output | grep "issuer:" | sed -n 's/.*CN=\([^;]*\).*/\1/p')
        issuers+="$issuer;"
        logI "  Checking connection to ${GREENW}$url${NC} (with SSL verification). Please wait..."
        logS "    Connection succeeded, the issuer of the website certificate is ${BLUEW}$issuer${NC}"
        # Let's attempt to see if this is public or private issuer
        # logI "    The issuer was trusted either because it is a publibly signed, or it is internally signed with a Internal Root CA trusted by MacOS Keychain..."
        # logI "       cURL used to test connectity, ALWAYS uses MacOS internal trusted certificates"
        # logI "       (even if specifying a certifice store without Internal Root CAs with the ${GREENW}--cacert${NC} switch."
        # logI "       Since a lot of CLI and a few GUIs program does not rely on the MacOS trusted certificates in Keychain Access,"
        # logI "       we need to provide a custom Certificate authority file (cacert.pem)"
        ((success_cnt++))
    else
        output=$(curl -s --insecure --head --verbose "$url" 2>&1)
        if [ $? -eq 0 ]; then
            issuer=$(echo "$output" | grep "issuer:" | sed -n 's/.*CN=\([^;]*\).*/\1/p')
            logI "  Checking connection to ${GREENW}$url${NC} (with SSL verification). Please wait..."
            logW "    Connection failed. The issuer of the website certificate is ${BLUEW}$issuer${NC}"
        else
            logI "  Checking connection to ${GREENW}$url${NC} (with SSL verification). Please wait..."
            logW "    Connection failed."
        fi
        if echo "$output" | grep "self signed certificate" > /dev/null 2>&1; then ((trustissue_cnt++)); fi # If the certificate is signed by a trusted issuer but is expired or has insecure ciphers refused by the server, this variable will not be set...
    fi
}

################################ RUNTIME #############################

# Let's start clean with unsetting all current Env variable for SSL Certificate Store
for var in "${variables[@]}"; do unset "$var"; done # Loop through the array and unset custom Certificate Store variable for various clients

# Execute the function to check web connectivity without SSL verification
logI "We'll now attempt to make a few web requests)..."
for site in "${websites[@]}"; do
  check_website_withoutSSL "$site"
  if [ $success_count -ge "$max_success" ]; then break; fi # If we could connect at least once, we know web connectivity can be established so skipping the other websites checks
done

# If we couldn't establish web connections, let's stop there since we have a proxy or internet connectivity issue...
if [[ $success_count -gt 0 ]]; then
  logS "    We were able to connect without checking for the validity of SSL/TLS certificate!"
  logW "We will now check if the web requests/responses are SSL intercepted!"
  logI "The issuer for each certificate website will be displayed and captured"
  for site in "${websites[@]}"; do
      check_website_withSSL "$site"
  done
else
  echo""; logE "We couldn't connect...\n Aborting..."
fi


if [[ $trustissue_cnt -gt 0 ]]; then
    echo ""; logW "We couldn't connect some websites while verifiying SSL certificates"
    logW "See cURL Error message below..."
    curl --head "$url" 2>&1 | tail -n +4 | grep -v "Established"
    logI "    We need to download Custom certificate Store (PEM file) and add internal signing Root CAs"
    logI "    then create persistent environment variables pointing to this custom Certificate Store..."
    source ./PEM_Var.sh
fi

if [[ $success_cnt -gt 0 ]]; then
    echo "issuers: $ssl_issuers"
    ssl_issuers=($(echo "${issuers[@]}" | tr ';' '\n' | sort -u))
    for issuer in "${ssl_issuers[@]}"; do
        logI "We have found the following issuer: $issuer"
    done
    sleep 300
    # Then compare issuer to public: /etc/ssl/cert.pem
    # And compare issuer to private: security -find
    echo "If Private: We will call PEM_VAR since we have found evidence of SSL Interception..." # source ./PEM_Var.sh
    logI "If Public: We have found no evidence that SSL Forward Inspection is being performed..."
    # logI "If you wish to set a customer Certificate Authority with internal Root signing CAs,"
    # logI "Please add your internal website, and filtered website to the \$websites variable in $0"
    # logI "Alternatively, call ./PEM_Var and it will do just that..."
fi


# Let's identify the logged-in user, it's home directory, it's default Shell interpreter and associated config file...
# source ./user_config.sh
# cacert_download                 # Let's download cacert.pem 