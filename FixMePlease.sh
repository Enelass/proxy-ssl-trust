#!/bin/zsh


# Download all this crap in /tmp
echo "Downloading all the required scripts to fix SSL and Proxy issues. Please wait..."
cd /tmp
curl -sk -L -O "https://github.com/Enelass/proxy-ssl-trust/archive/refs/heads/main.zip"
unzip -q -o main.zip
cd proxy-ssl-trust-main
source ./connect_noproxy.sh
source ./PEM_Var.sh