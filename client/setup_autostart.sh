#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

# Get the absolute path to the rc4_client directory
CLIENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CLIENT_BINARY="$CLIENT_DIR/rc4_client"
CLIENT_SOURCE="$CLIENT_DIR/rc4_client.c"

# Check if OpenSSL is installed at the expected location
OPENSSL_PREFIX="/usr/local/ssl"
if [ ! -d "$OPENSSL_PREFIX" ] || [ ! -f "$OPENSSL_PREFIX/lib/libssl.so" ]; then
  echo "OpenSSL not found at $OPENSSL_PREFIX. Installing OpenSSL 1.0.2u..."
  
  # Create build directory
  OPENSSL_VERSION="1.0.2u"
  SRC_DIR=$(mktemp -d)
  
  # Download and extract OpenSSL
  cd "$SRC_DIR"
  if ! wget -q "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"; then
    echo "Failed to download OpenSSL. Please check your internet connection."
    exit 1
  fi
  
  tar -xzf "openssl-$OPENSSL_VERSION.tar.gz"
  cd "openssl-$OPENSSL_VERSION"
  
  # Build and install OpenSSL
  ./config --prefix="$OPENSSL_PREFIX" --openssldir="$OPENSSL_PREFIX" shared
  make clean
  make -j$(nproc)
  make install_sw
  ldconfig
  
  # Clean up
  cd "$CLIENT_DIR"
  rm -rf "$SRC_DIR"
  
  echo "OpenSSL $OPENSSL_VERSION has been installed to $OPENSSL_PREFIX"
else
  echo "OpenSSL installation found at $OPENSSL_PREFIX"
fi

# Compile the client if source exists and binary doesn't exist or needs recompilation
if [ -f "$CLIENT_SOURCE" ]; then
  if [ ! -x "$CLIENT_BINARY" ] || [ "$CLIENT_SOURCE" -nt "$CLIENT_BINARY" ]; then
    echo "Compiling rc4_client..."
    gcc "$CLIENT_SOURCE" -o "$CLIENT_BINARY" \
      -I"$OPENSSL_PREFIX/include" \
      -L"$OPENSSL_PREFIX/lib" \
      -lssl -lcrypto -ldl -pthread
    
    if [ $? -eq 0 ]; then
      echo "Compilation successful"
      chmod +x "$CLIENT_BINARY"
    else
      echo "Error: Compilation failed"
      exit 1
    fi
  else
    echo "Binary already exists and is up to date"
  fi
else
  echo "Error: Source file $CLIENT_SOURCE not found"
  exit 1
fi

# Ensure the binary exists and is executable
if [ ! -x "$CLIENT_BINARY" ]; then
  echo "Error: $CLIENT_BINARY not found or not executable after compilation attempt"
  exit 1
fi

# Create systemd service file
cat > /etc/systemd/system/rc4-client.service << EOF
[Unit]
Description=RC4 Client Service
After=network.target

[Service]
Type=simple
Environment="LD_LIBRARY_PATH=/usr/local/ssl/lib:\$LD_LIBRARY_PATH"
WorkingDirectory=$CLIENT_DIR
ExecStart=$CLIENT_BINARY
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable and start the service
systemctl daemon-reload
systemctl enable rc4-client.service
systemctl start rc4-client.service

echo "RC4 client has been set up to start automatically on boot"
echo "Current status:"
systemctl status rc4-client.service 