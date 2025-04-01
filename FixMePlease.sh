#!/bin/zsh


# Download all this crap in /tmp
cd /tmp
curl -k -L -O "https://github.com/Enelass/proxy-ssl-trust/archive/refs/heads/main.zip"
unzip main.zip
cd proxy-ssl-trust-main
source ./connect_noproxy.sh
source ./PEM_Var.sh