#!/bin/bash

# Set up the main directory where all CA and certificate files will be stored
MAIN_DIR=./DIR
PASSWORD="password"  # Set the password to be used for the keys
mkdir -p $MAIN_DIR

# Input file paths
CERT_CHAIN="cert_chain.pem"  # cert_chain.pem extracted from PKCS#12 file
P12_FILE="new_client.p12"    # Output PKCS#12 file
PASSWORD="password" # Password for PKCS#12 file

# Temporary directories for extracting certs
TEMP_DIR="temp"
CA_DIR="$TEMP_DIR/ca"
CLIENT_DIR="$TEMP_DIR/client"
mkdir -p $TEMP_DIR $CA_DIR $CLIENT_DIR

echo 1000 > $MAIN_DIR/serial

parse_subject(){
    input=$1
    original_IFS=$IFS
    input="${input//subject=/}"
    output=""
    IFS=',' # Set Internal Field Separator to split by '/'
    first=true # A flag to handle the first entry
    for pair in $input; do
        # Step 3: Check if there's a '=' in the pair to separate key and value
        if [[ "$pair" == *'='* ]]; then
            # Split by '=' into key and value
            IFS='=' read -r key value <<< "$pair"
            # Step 4: Remove spaces from key and value
            #key="${key//[[:space:]]/}"
            #value="${value//[[:space:]]/}"
            key=$(echo $key | sed 's/^\s*//;s/\s*$//') # trim spaces start and end
            value=$(echo $value | sed 's/^\s*//') # trim spaces start and end
            #echo $key
            #echo $value
            # Step 5: Format the output as /type=value
            if [ "$first" = true ]; then
                output+="/${key}=${value}"  # First pair, no leading '/'
                first=false
            else
                output+="/${key}=${value}"  # Subsequent pairs, with leading '/'
            fi
        fi
    done
    IFS=$original_IFS
    output="${output//,/\/}"
    echo "$output"
    #CLIENT_SUBJECT=$output
}

# Step 1: Split the cert_chain.pem file into individual certs (client cert, intermediates, root cert)
echo "Splitting the cert_chain.pem file into individual certificates..."
awk 'BEGIN {c=0} /-----BEGIN CERTIFICATE-----/ {c++} {print > "cert" c ".pem"}' $CERT_CHAIN

# Step 2: Move the extracted certificates into the appropriate directories
mv cert1.pem $CLIENT_DIR/client_cert.pem  # Client certificate
mv cert2.pem $CA_DIR/intermediate.pem     # Intermediate certificate (first intermediate)
mv cert3.pem $CA_DIR/root.pem             # Root certificate (last cert)



# Root CA setup
echo "### Generating Root CA ###"
# Generate root CA private key with a password (passphrase protection)
openssl genpkey -algorithm RSA -out $MAIN_DIR/rootCA.key -aes256 -pass pass:$PASSWORD

ROOTCA_SUBJECT=$(openssl x509 -in $CA_DIR/root.pem -noout -subject | sed 's/^subject= //')
ROOTCA_SUBJECT=$(echo $ROOTCA_SUBJECT | sed 's/^\s*//;s/\s*$//')  # Trim spaces from start and end
echo "[] Extracted Subject: $ROOTCA_SUBJECT"
ROOTCA_SUBJECT=$(parse_subject "$ROOTCA_SUBJECT")
echo "[] Parsed Subject: $ROOTCA_SUBJECT"


# Root CA Certificate Details (no prompts)
#ROOT_CN="My Root CA"
#ROOT_COUNTRY="US"
#ROOT_STATE="ExampleState"
#ROOT_LOCALITY="ExampleCity"
#ROOT_ORG="MyOrg"
#ROOT_OU="Root CA Organization"
#openssl req -key $MAIN_DIR/rootCA.key -new -x509 -out $MAIN_DIR/rootCA.crt -days 3650 -sha256 \
#  -subj "/C=$ROOT_COUNTRY/ST=$ROOT_STATE/L=$ROOT_LOCALITY/O=$ROOT_ORG/OU=$ROOT_OU/CN=$ROOT_CN" -passin pass:$PASSWORD

# Generate the Root CA certificate
openssl req -key $MAIN_DIR/rootCA.key -new -x509 -out $MAIN_DIR/rootCA.crt -days 3650 -sha256 \
  -subj "$ROOTCA_SUBJECT" -passin pass:$PASSWORD



echo "### Generating Intermediate CA ###"

INTERMEDIATE_SUBJECT=$(openssl x509 -in $CA_DIR/intermediate.pem -noout -subject | sed 's/^subject= //')
INTERMEDIATE_SUBJECT=$(echo $INTERMEDIATE_SUBJECT | sed 's/^\s*//;s/\s*$//')  # Trim spaces from start and end
echo "[] Extracted Subject: $INTERMEDIATE_SUBJECT"
INTERMEDIATE_SUBJECT=$(parse_subject "$INTERMEDIATE_SUBJECT")
echo "[] Parsed Subject: $INTERMEDIATE_SUBJECT"


# Generate intermediate CA private key with a password (passphrase protection)
openssl genpkey -algorithm RSA -out $MAIN_DIR/intermediate.key -aes256 -pass pass:$PASSWORD

#INTERMEDIATE_CN="My Intermediate CA"
#INTERMEDIATE_COUNTRY="US"
#INTERMEDIATE_STATE="ExampleState"
#INTERMEDIATE_LOCALITY="ExampleCity"
#INTERMEDIATE_ORG="MyOrg"
#INTERMEDIATE_OU="Intermediate CA Organization"
#openssl req -key $MAIN_DIR/intermediate.key -new -out $MAIN_DIR/intermediate.csr \
#  -subj "/C=$INTERMEDIATE_COUNTRY/ST=$INTERMEDIATE_STATE/L=$INTERMEDIATE_LOCALITY/O=$INTERMEDIATE_ORG/OU=$INTERMEDIATE_OU/CN=$INTERMEDIATE_CN" -passin pass:$PASSWORD

openssl req -key $MAIN_DIR/intermediate.key -new -out $MAIN_DIR/intermediate.csr \
  -subj "$INTERMEDIATE_SUBJECT" -passin pass:$PASSWORD

# Create an OpenSSL configuration file to include CA:TRUE for the intermediate certificate
cat > $MAIN_DIR/intermediate_ext.cnf <<EOL
[ v3_ca ]
# Basic Constraints for the intermediate CA
basicConstraints = CA:TRUE
keyUsage = digitalSignature, cRLSign, keyCertSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOL

# Sign Intermediate certificate with Root CA and use the configuration file to set it as a CA
openssl x509 -req -in $MAIN_DIR/intermediate.csr -CA $MAIN_DIR/rootCA.crt -CAkey $MAIN_DIR/rootCA.key -CAcreateserial \
  -out $MAIN_DIR/intermediate.crt -days 3650 -sha256 -extfile $MAIN_DIR/intermediate_ext.cnf -extensions v3_ca -passin pass:$PASSWORD

echo "### Generating Client Certificate ###"


echo "Extracting subject from the client certificate..."
CLIENT_SUBJECT=$(openssl x509 -in $CLIENT_DIR/client_cert.pem -noout -subject | sed 's/^subject= //')
CLIENT_SUBJECT=$(echo $CLIENT_SUBJECT | sed 's/^\s*//;s/\s*$//')  # Trim spaces from start and end
echo "[] Extracted Subject: $CLIENT_SUBJECT"
CLIENT_SUBJECT=$(parse_subject "$CLIENT_SUBJECT")
echo "[] Parsed Subject: $CLIENT_SUBJECT"


# Generate client private key with a password (passphrase protection)
openssl genpkey -algorithm RSA -out $MAIN_DIR/client.key -aes256 -pass pass:$PASSWORD

# Client CSR Details (no prompts)
#CLIENT_CN="client.example.com"
#CLIENT_COUNTRY="US"
#CLIENT_STATE="ExampleState"
#CLIENT_LOCALITY="ExampleCity"
#CLIENT_ORG="MyOrg"
#CLIENT_OU="Client Organization"
#openssl req -key $MAIN_DIR/client.key -new -out $MAIN_DIR/client.csr \
#  -subj "/C=$CLIENT_COUNTRY/ST=$CLIENT_STATE/L=$CLIENT_LOCALITY/O=$CLIENT_ORG/OU=$CLIENT_OU/CN=$CLIENT_CN" -passin pass:$PASSWORD

openssl req -key $MAIN_DIR/client.key -new -out $MAIN_DIR/client.csr \
  -subj "$CLIENT_SUBJECT" -passin pass:$PASSWORD



# Sign Client certificate with Intermediate CA
openssl x509 -req -in $MAIN_DIR/client.csr -CA $MAIN_DIR/intermediate.crt -CAkey $MAIN_DIR/intermediate.key -CAcreateserial \
  -out $MAIN_DIR/client.crt -days 365 -sha256 -passin pass:$PASSWORD

# Verify the full certificate chain by concatenating the Root and Intermediate certificates
echo "### Verifying Client Certificate ###"
cat $MAIN_DIR/rootCA.crt $MAIN_DIR/intermediate.crt > $MAIN_DIR/ca-chain.crt
openssl verify -CAfile $MAIN_DIR/ca-chain.crt $MAIN_DIR/client.crt

echo "### Root CA, Intermediate CA, and Client Certificate generation completed successfully ###"

# Create a new PKCS#12 file containing the new client cert, private key, and CA chain
echo "Creating new PKCS#12 file..."
openssl pkcs12 -export -out $P12_FILE -inkey $MAIN_DIR/client.key -in $MAIN_DIR/client.crt -certfile $MAIN_DIR/intermediate.crt -password pass:$PASSWORD

echo "New PKCS#12 file created: $P12_FILE"
