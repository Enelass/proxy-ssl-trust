#!/bin/zsh

afplay ./Two_Swords.m4a &
source ./stderr_stdout_syntax.sh

################################ VARIABLES #############################
# List of websites to check for webconn_checks()
websites=("https://photonsec.com.au" "https://www.google.com" "https://www.wikipedia.org")
max_success=1   # Maximum number of successful web connections to stop after webconn_checks()
success_count=0 # Counter for successful web connections for webconn_checks()
curltimeout=5  # Number of seconds after which cURL will give up connecting for check_website()
dns_server="8.8.8.8"  # DNS Server IP for 


################################ FUNCTIONS #############################
# Function to ping known public IP addresses
ping_known_ips() {
  # Google, Cloudflare & OpenDNS
  local ip_addresses=("8.8.8.8" "1.1.1.1" "208.67.222.222")
  local retries=3; local timeout=2

    echo ""; logI "Now testing internet connectivity, we 'll be pinging known public IP addresses..."
    for ip in "${ip_addresses[@]}"; do
        if ping -c $retries -W $timeout $ip > /dev/null 2>&1; then
            logS "   Pinging $ip... It's reachable."
            sleep 2; echo -en "\r\033[2K\033[F\033[2K";  # Clear the current line and the one before
            internet_conn=true
        else
            logW "   Pinging $ip... It's not reachable! ICMP probes might be blocked or you do not have internet connectivity."
            sleep 2; echo -en "\r\033[2K\033[F\033[2K";  # Clear the current line and the one before
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
    logI "  Checking connection to $url. Please wait..."
    if curl -skI --connect-timeout $curltimeout --max-time $curltimeout "$url" | grep -E "HTTP/2 200|HTTP/1.1 200" > /dev/null; then
        logS "    Connection succeeded: $url"
        ((success_count++))
    else
        logW "    Connection failed: $url"
    fi
    sleep 2;
    echo -en "\r\033[2K\033[F\033[2K\033[F\033[2K"
}

# Function to check web connectivity against multiple websites
webconn_checks() {
   logI "We'll now attempt to make a few web requests, $curltimeout seconds timeout per attempt)..."
  for site in "${websites[@]}"; do
    check_website "$site"
    if [ "$success_count" -ge "$max_success" ]; then
      break
    fi
  done
}

# Function to check DNS and ICMP connectivity
conn_checks(){
  # We start by checking interfaces and private IP addresses, if interfaces are all down, there is nothing for us to do...
  source ./interfaces.sh
 
  # Call the function to test internet connectivity using ping (ICMP echo)
  ping_known_ips
  echo ""

  if [[ -n $pac_url ]]; then
    logI "A pac (Proxy Auto-Configuration) file URL was found and is reachable... We'll now look for a working proxy in it..."    
    source ./pac_proxy_extract.sh
  else
    logE "No pac (Proxy Auto-Configuration) file URLs were found and at reach... you might need to manually set PAC_FILE_URL in ./pac_proxy_extract.sh"
  fi
}


################################ RUNTIME #############################

clear
unset {ALL,all,HTTP,http,HTTPS,https}_proxy  # We need to start clean... no proxy settings!
logI "Proxy environment variables have been unset."

# Execute the function to check webconnectivity
webconn_checks

# If we couldn't establish web connections, let's check basic network requirements and look for proxy settings
if [[ $success_count -gt 0 ]]; then
  echo ""; logI "We were able to connect without proxy..."
  # Next check_for_ssl_interception``
else
  echo"";   logW "We couldn't connect to any websites, so we might be proxied...\n"
  logI "Performing additional diagnostics. Let's inspect the NICs..."
  conn_checks
  if [[ -n "$workingproxy" ]]; then
    echo ''; logI "Good news, we have found a pac file and associated/working proxy, let's install Alpaca to reap the benefits of it..."
    source ./AlpacaSetup.sh
  else
    logW "We haven't found any working proxy from the PAC file, either they're all down, or we were too aggressive on the timing"
    logE "Please increase timeout variable in pac_proxy_extract.sh and try again..." 
  fi
fi