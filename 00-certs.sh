#!/bin/bash

# Default values
CERT_DIR="$PWD/certs"
OVERWRITE_CERTS="no"
REGEN_CA="no"
REGEN_LDAP_CERTS="no"
CN="openldap.local"
SAN="DNS:openldap.local,IP:127.0.0.1"

# === Usage ===
usage() {
  echo "Usage: $0 [--overwrite yes|no] [--regen-ca yes|no] [--regen-ldap-certs yes|no]"
  exit 1
}

# === Parse CLI arguments ===
while [[ $# -gt 0 ]]; do
  case $1 in
    --overwrite)
      case "$2" in
        yes|no) OVERWRITE_CERTS="$2" ;;
        *) echo "Invalid --overwrite value: $2"; usage ;;
      esac
      shift ;;
    --regen-ca)
      case "$2" in
        yes|no) REGEN_CA="$2" ;;
        *) echo "Invalid --regen-ca value: $2"; usage ;;
      esac
      shift ;;
    --regen-ldap-certs)
      case "$2" in
        yes|no) REGEN_LDAP_CERTS="$2" ;;
        *) echo "Invalid --regen-ldap-certs value: $2"; usage ;;
      esac
      shift ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
  shift
done

# Paths
CA_KEY_PATH="$CERT_DIR/openldapCA.key"
CA_CERT_PATH="$CERT_DIR/openldapCA.crt"
LDAP_KEY_PATH="$CERT_DIR/openldap.key"
LDAP_CRT_PATH="$CERT_DIR/openldap.crt"
CSR_PATH="$CERT_DIR/openldap.csr"
OPENSSL_CNF="$CERT_DIR/openssl.cnf"

# Generate certificates only if overwrite=yes or certs don't exist
mkdir -p "$CERT_DIR"

if [[ "$REGEN_CA" == "yes" || "$OVERWRITE_CERTS" == "yes" || ! -f "$CA_CERT_PATH" ]]; then
  echo "Generating CA certificate..."
  openssl req -new -x509 -nodes -days 1095 -keyout "$CA_KEY_PATH" -out "$CA_CERT_PATH" -subj "/CN=OpenLDAP-CA"
  chmod 644 "$CA_CERT_PATH"
fi

if [[ "$REGEN_LDAP_CERTS" == "yes" || "$OVERWRITE_CERTS" == "yes" || ! -f "$LDAP_CRT_PATH" || ! -f "$LDAP_KEY_PATH" ]]; then
  echo "Generating OpenLDAP certificates..."
  openssl genrsa -out "$LDAP_KEY_PATH" 2048

  # Generate CSR with SAN
  cat > "$OPENSSL_CNF" <<EOF
[ req ]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[ req_distinguished_name ]
CN = $CN

[ v3_req ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = $SAN
EOF

  openssl req -new -key "$LDAP_KEY_PATH" -out "$CSR_PATH" -config "$OPENSSL_CNF"
  openssl x509 -req -in "$CSR_PATH" -CA "$CA_CERT_PATH" -CAkey "$CA_KEY_PATH" -CAcreateserial -out "$LDAP_CRT_PATH" -days 365 -extensions v3_req -extfile "$OPENSSL_CNF"

  chmod 600 "$LDAP_KEY_PATH"
  chmod 644 "$LDAP_CRT_PATH"
fi

# Configure permissions for the openldap container
sudo chown -R 1001:1001 $CERT_DIR

# Cleanup
rm -f "$CSR_PATH" "$OPENSSL_CNF"

echo "Certificates have been generated and stored in $CERT_DIR"