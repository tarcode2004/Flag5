#!/bin/bash
set -euo pipefail
OPENSSL_PREFIX="/usr/local/ssl"
CLIENT_DIR="./client"
CLIENT_SRC="$CLIENT_DIR/rc4_client.c"
CLIENT_BIN="$CLIENT_DIR/rc4_client"

echo "[10_verify_ssl] Compiling RC4 client..."
if [ ! -d "$CLIENT_DIR" ]; then
    echo "[!] Error: Client directory not found at $CLIENT_DIR"
    exit 1
fi

if [ ! -f "$CLIENT_SRC" ]; then
    echo "[!] Error: Client source not found at $CLIENT_SRC"
    exit 1
fi

# Compile the RC4 client
gcc -o "$CLIENT_BIN" "$CLIENT_SRC" -L"$OPENSSL_PREFIX/lib" -I"$OPENSSL_PREFIX/include" -lssl -lcrypto
if [ ! -f "$CLIENT_BIN" ]; then
    echo "[!] Error: Failed to compile RC4 client"
    exit 1
fi
chmod +x "$CLIENT_BIN"

echo "[10_verify_ssl] Testing SSL connection using custom RC4 client..."
CLIENT_OUTPUT=$("$CLIENT_BIN")
echo "$CLIENT_OUTPUT"

# Check if the connection was successful
if echo "$CLIENT_OUTPUT" | grep -q "SSL Handshake successful"; then
    CIPHER_USED=$(echo "$CLIENT_OUTPUT" | grep "Cipher:" | sed 's/.*Cipher: //')
    echo "[10_verify_ssl] Successfully connected. Cipher reported: ${CIPHER_USED}"
    
    if [[ "$CIPHER_USED" == *"RC4-SHA"* ]]; then
        echo "[10_verify_ssl] Verified RC4-SHA cipher is being used."
    else
        echo "[!] Warning: Expected RC4-SHA but got ${CIPHER_USED}."
        exit 1
    fi
else
    echo "[!] Failed to connect using RC4 client."
    exit 1
fi
