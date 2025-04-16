#!/bin/zsh
if [ "$EUID" -eq 0 ]; then
	echo "Please do not run as root or sudo... This is a user-context script"
fi

if [ ! -d "$HOME/Applications/" ]; then mkdir -p "$HOME/Applications/"; fi

echo "Downloading all the required scripts to fix SSL and Proxy issues. Please wait..."
cd $HOME/Applications/
curl -sk -L -O "https://github.com/Enelass/proxy-ssl-trust/archive/refs/heads/main.zip"
unzip -q -o main.zip
rm main.zip
mv proxy-ssl-trust-main proxy-ssl-trust
cd proxy-ssl-trust
source ./proxy_ssl_trust.sh --proxy