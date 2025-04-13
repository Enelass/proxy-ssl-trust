#!/bin/zsh
local scriptname="$0"
local current_dir=$(dirname $(realpath $0))
if [[ -z ${logI-} ]]; then source "$current_dir/../stderr_stdout_syntax.sh"; fi
# source "$current_dir/../play.sh"

################################ VARIABLES #############################
# List of websites to check for webconn_checks()
website_regex="^https:\/\/([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}\/?$"
websites=("https://photonsec.com.au" "https://www.google.com" "https://www.microsoft.com")  # List of websites to check for check_website()
    # Read additional websites from the configuration file
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and lines starting with "#"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ $website_regex ]]; then websites+=("$line"); fi
    done < "$current_dir/websites.config"

success_count=0; max_success=1;   # Maximum number of successful web connections to stop after webconn_checks() & Counter for successful web connections for webconn_checks()
fail_count=0; max_fail=10         # Counter for failed web connections for webconn_checks(), It'll stop checking after the first 10 websites
curltimeout=5   # Number of seconds after which cURL will give up connecting for check_website()


################################ FUNCTIONS #############################
# Function to ping known public IP addresses
ping_known_ips() {
  # Google, Cloudflare & OpenDNS
  local ip_addresses=("8.8.8.8" "1.1.1.1" "208.67.222.222")
  local retries=3; local timeout=2

    echo ""; logI "Now testing internet connectivity, we'll be pinging known public IP addresses..."
    for ip in "${ip_addresses[@]}"; do
        if ping -c $retries -W $timeout $ip > /dev/null 2>&1; then
            logS "   Pinging $ip... It's reachable."
            sleep 1; echo -en "\r\033[2K\033[F\033[2K";  # Clear the current line and the one before
            internet_conn=true
        else
            logW "   Pinging $ip... It's not reachable! ICMP probes might be blocked or you do not have internet connectivity."
            sleep 1; echo -en "\r\033[2K\033[F\033[2K";  # Clear the current line and the one before
        fi
    done

    if [[ $internet_conn=true ]]; then
      logS "We have internet connectivity since some pings went though! Let's now look for a proxy URL we can use..."
    else
      logW "All the ping probes failed. We might not be connected to the internet, in which case the next steps will also fail..."
      logW "However we might also have Ping probes blocked by a network appliances, in which case we can still go ahead to find and test a proxy..."
    fi
}


# Function to check if a website is reachable
check_website() {
    url=$1
    if curl -skI --connect-timeout $curltimeout --max-time $curltimeout "$url" | grep -E "HTTP/2 200|HTTP/1.1 200" > /dev/null; then
        echo -en "\r\033[2K\033[F\033[2K\033[F\033[2K"
        logI "  Checking connection to $url. Please wait..."
        logS "    Connection succeeded: $url"
        ((success_count++))
    else
        echo -en "\r\033[2K\033[F\033[2K\033[F\033[2K"
        logI "  Checking connection to $url. Please wait..."
        logW "    Connection failed: $url"
        ((fail_count++))
    fi
}

# Function to check web connectivity against multiple websites
webconn_checks() {
  logI "We'll now attempt to make a few web requests without ignoring SSL verification, $curltimeout seconds timeout per attempt)..."; echo; echo
  for site in "${websites[@]}"; do
    check_website "$site"
    if [ "$fail_count" -ge "$max_fail" ]; then
      break
    fi
  done
}

# Function to check DNS and ICMP connectivity
conn_checks(){
  # We start by checking interfaces and private IP addresses, if interfaces are all down, there is nothing for us to do...
  source "$current_dir/interfaces.sh"
 
  # Call the function to test internet connectivity using ping (ICMP echo)
  ping_known_ips
  echo

  if [[ -n $pac_url ]]; then
    logI "A pac (Proxy Auto-Configuration) file URL was found and is reachable... We'll now look for a working proxy in it..."    
    source "$current_dir/pac_proxy_extract.sh"
  else
    logE "No pac (Proxy Auto-Configuration) file URLs were found and at reach... you might need to manually set PAC_FILE_URL in ./pac_proxy_extract.sh"
  fi
}


################################ RUNTIME #############################

unset {ALL,all,HTTP,http,HTTPS,https}_proxy  # We need to start clean... no proxy settings!

echo; logI "  ---   ${PINK}SCRIPT: $scriptname${NC}   ---"
logI "        ${PINK}     It is intended to check if connection can be established without proxy${NC}"
logI "Proxy environment variables have been unset."

# Execute the function to check webconnectivity
webconn_checks
echo -en "\r\033[2K\033[F\033[2K\033[F\033[2K"

# If we couldn't establish web connections against two websites, let's check basic network requirements and look for proxy settings
if [[ $fail_count -gt 1 ]]; then
  logI "We couldn't connect directly to most websites, so we might be proxied 👍...\n"
  logI "Performing additional diagnostics. Let's inspect the NICs..."
  conn_checks
  if [[ -n "$workingproxy" ]]; then
    logI "Good news, we have found a pac file and a working proxy, let's install Alpaca to make use of it..."
    source "$(dirname $(realpath $0))/AlpacaSetup.sh"
  else
    logW "We haven't found any working proxy from the PAC file, either they're all down, or we were too aggressive on the timing"
    logE "Please increase timeout variable in pac_proxy_extract.sh and try again..." 
  fi
else
  echo; logI "We were able to connect without proxy to most websites 👍..."
  logI "We will now test web requests and whether these are SSL intercepted or not..."
  source "$(dirname $(realpath $0))/connect_ssl.sh"
fi