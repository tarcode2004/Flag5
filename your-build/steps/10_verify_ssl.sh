#!/bin/bash
set -euo pipefail
OPENSSL_PREFIX="/usr/local/ssl"
CUSTOM_OPENSSL_CLIENT="$OPENSSL_PREFIX/bin/openssl"

echo "[10_verify_ssl] Testing SSL connection using custom OpenSSL client..."
if "$CUSTOM_OPENSSL_CLIENT" s_client -connect localhost:443 -cipher RC4-SHA -no_ssl3 -no_tls1_3 -no_tls1_2 -no_tls1_1 -tls1 <<< "" > /dev/null 2>&1; then
    echo "[10_verify_ssl] Successfully connected using RC4-SHA."
    CIPHER_USED=$("$CUSTOM_OPENSSL_CLIENT" s_client -connect localhost:443 -cipher RC4-SHA -no_ssl3 -no_tls1_3 -no_tls1_2 -no_tls1_1 -tls1 <<< "" 2>/dev/null | grep "Cipher    :" | sed 's/.*Cipher    : //')
    echo "[10_verify_ssl] Cipher reported by server: ${CIPHER_USED}"
    if [[ "$CIPHER_USED" != "RC4-SHA" ]]; then
        echo "[!] Warning: Expected RC4-SHA but got ${CIPHER_USED}."
    fi
else
    echo "[!] Failed to connect using custom OpenSSL client with RC4-SHA."
    exit 1
fi
