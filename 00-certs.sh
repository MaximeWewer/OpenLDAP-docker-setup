#!/bin/bash

# Directory where certificates will be stored
CERT_DIR="$PWD/certs"

# Create the directory if it doesn't exist
mkdir -p "$CERT_DIR"

# Generate the private key and the Certificate Authority (CA) certificate
openssl req -new -x509 -nodes -keyout "$CERT_DIR/openldapCA.key" -out "$CERT_DIR/openldapCA.crt" -days 1095 -subj "/CN=ldap-ca"

# Generate the private key for the LDAP server
openssl genrsa -out "$CERT_DIR/openldap.key" 2048

# Create a Certificate Signing Request (CSR)
openssl req -new -key "$CERT_DIR/openldap.key" -out "$CERT_DIR/openldap.csr" -subj "/CN=ldap"

# Sign the CSR using the CA
openssl x509 -req -in "$CERT_DIR/openldap.csr" -CA "$CERT_DIR/openldapCA.crt" -CAkey "$CERT_DIR/openldapCA.key" -CAcreateserial -out "$CERT_DIR/openldap.crt" -days 365

# Set appropriate permissions
chmod 600 "$CERT_DIR/openldap.key"
chmod 644 "$CERT_DIR/openldap.crt"
chmod 644 "$CERT_DIR/openldapCA.crt"

echo "Certificates have been generated and stored in $CERT_DIR"
