#!/bin/bash

# Set up the main directory where all CA and certificate files will be stored
MAIN_DIR=./DIR
PASSWORD="password"  # Set the password to be used for the keys

# Create the directory for storing all files
mkdir -p $MAIN_DIR

# Initialize the serial files
echo 1000 > $MAIN_DIR/serial

# Root CA setup
echo "### Generating Root CA ###"
# Generate root CA private key with a password (passphrase protection)
openssl genpkey -algorithm RSA -out $MAIN_DIR/rootCA.key -aes256 -pass pass:$PASSWORD

# Root CA Certificate Details (no prompts)
ROOT_CN="My Root CA"
ROOT_COUNTRY="US"
ROOT_STATE="ExampleState"
ROOT_LOCALITY="ExampleCity"
ROOT_ORG="MyOrg"
ROOT_OU="Root CA Organization"

# Generate the Root CA certificate
openssl req -key $MAIN_DIR/rootCA.key -new -x509 -out $MAIN_DIR/rootCA.crt -days 3650 -sha256 \
  -subj "/C=$ROOT_COUNTRY/ST=$ROOT_STATE/L=$ROOT_LOCALITY/O=$ROOT_ORG/OU=$ROOT_OU/CN=$ROOT_CN" -passin pass:$PASSWORD

# Intermediate CA setup
echo "### Generating Intermediate CA ###"
# Generate intermediate CA private key with a password (passphrase protection)
openssl genpkey -algorithm RSA -out $MAIN_DIR/intermediate.key -aes256 -pass pass:$PASSWORD

# Intermediate CSR Details (no prompts)
INTERMEDIATE_CN="My Intermediate CA"
INTERMEDIATE_COUNTRY="US"
INTERMEDIATE_STATE="ExampleState"
INTERMEDIATE_LOCALITY="ExampleCity"
INTERMEDIATE_ORG="MyOrg"
INTERMEDIATE_OU="Intermediate CA Organization"

openssl req -key $MAIN_DIR/intermediate.key -new -out $MAIN_DIR/intermediate.csr \
  -subj "/C=$INTERMEDIATE_COUNTRY/ST=$INTERMEDIATE_STATE/L=$INTERMEDIATE_LOCALITY/O=$INTERMEDIATE_ORG/OU=$INTERMEDIATE_OU/CN=$INTERMEDIATE_CN" -passin pass:$PASSWORD

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

# Client certificate setup
echo "### Generating Client Certificate ###"
# Generate client private key with a password (passphrase protection)
openssl genpkey -algorithm RSA -out $MAIN_DIR/client.key -aes256 -pass pass:$PASSWORD

# Client CSR Details (no prompts)
CLIENT_CN="client.example.com"
CLIENT_COUNTRY="US"
CLIENT_STATE="ExampleState"
CLIENT_LOCALITY="ExampleCity"
CLIENT_ORG="MyOrg"
CLIENT_OU="Client Organization"

openssl req -key $MAIN_DIR/client.key -new -out $MAIN_DIR/client.csr \
  -subj "/C=$CLIENT_COUNTRY/ST=$CLIENT_STATE/L=$CLIENT_LOCALITY/O=$CLIENT_ORG/OU=$CLIENT_OU/CN=$CLIENT_CN" -passin pass:$PASSWORD

# Sign Client certificate with Intermediate CA
openssl x509 -req -in $MAIN_DIR/client.csr -CA $MAIN_DIR/intermediate.crt -CAkey $MAIN_DIR/intermediate.key -CAcreateserial \
  -out $MAIN_DIR/client.crt -days 365 -sha256 -passin pass:$PASSWORD

# Verify the full certificate chain by concatenating the Root and Intermediate certificates
echo "### Verifying Client Certificate ###"
cat $MAIN_DIR/rootCA.crt $MAIN_DIR/intermediate.crt > $MAIN_DIR/ca-chain.crt
openssl verify -CAfile $MAIN_DIR/ca-chain.crt $MAIN_DIR/client.crt

echo "### Root CA, Intermediate CA, and Client Certificate generation completed successfully ###"
