#!/bin/zsh

cacert_integrity_check(){	
	log "Info    -    Checking $customcacert integrity..."
  local cacert_file=$1
  local n=0
  local cert_file

  # Read the entire cacert.pem file into a variable
	pem_contents=$(<"$cacert_file")

	# Initialize an empty array to hold individual certificates
	certificates=()

	# Use a while loop to extract each certificate and store it in an array
	while [[ "$pem_contents" =~ (-----BEGIN CERTIFICATE-----(.*?)
	-----END CERTIFICATE-----) ]]; do
	    # Append the matched certificate to the certificates array
	    certificates+=( "${BASH_REMATCH[0]}" )

	    # Remove the processed certificate from the pem_contents
	    pem_contents=${pem_contents#*-----END CERTIFICATE-----}
	done

	# Now process each certificate using openssl
	for cert in "${certificates[@]}"; do
	    # If you need to decode the certificate with openssl, you can do like this:
	    echo "$cert" | openssl x509 -noout -text
	done
	sleep 600
}

#!/bin/bash

# Path to the cacert.pem file
CACERT_PEM="~/.config/cacert/cacert.pem"

# Read the cacert.pem file and split it into individual certificates.
certificates=$(awk 'BEGIN{c=0;} /-----BEGIN CERTIFICATE-----/{c++} {print >"cert" c ".pem"}' $CACERT_PEM)

# Loop through each generated certificate file.
for certfile in cert*.pem; do
    # Verify the certificate using openssl
    openssl x509 -in "$certfile" -noout -text &> /dev/null
    if [ $? -eq 0 ]; then
        echo "Certificate $certfile is valid."
    else
        echo "Certificate $certfile is invalid."
    fi
done

# Cleanup temporary certificate files
rm cert*.pem