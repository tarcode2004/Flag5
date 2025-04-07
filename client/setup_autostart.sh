#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

# Get the absolute path to the rc4_client directory
CLIENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CLIENT_BINARY="$CLIENT_DIR/rc4_client"
CLIENT_SOURCE="$CLIENT_DIR/rc4_client.c"

# Check and install prerequisites
check_install_prerequisites() {
  echo "Checking for build prerequisites..."
  if ! command -v make &>/dev/null || ! command -v gcc &>/dev/null; then
    echo "Installing build dependencies..."
    apt-get update
    apt-get install -y build-essential libpcre3-dev zlib1g-dev libtool wget curl make libexpat1-dev
    if [ $? -ne 0 ]; then
      echo "Failed to install build dependencies. Exiting."
      exit 1
    fi
    echo "Build dependencies installed successfully."
  else
    echo "Build tools already installed."
  fi
}

# Check if OpenSSL is installed at the expected location
install_openssl() {
  OPENSSL_PREFIX="/usr/local/ssl"
  if [ ! -d "$OPENSSL_PREFIX" ] || [ ! -f "$OPENSSL_PREFIX/lib/libssl.so" ]; then
    echo "OpenSSL not found at $OPENSSL_PREFIX. Installing OpenSSL 1.0.2u..."
    
    # Ensure prerequisites are installed
    check_install_prerequisites
    
    # Create build directory
    OPENSSL_VERSION="1.0.2u"
    SRC_DIR=$(mktemp -d)
    
    # Download and extract OpenSSL
    cd "$SRC_DIR"
    if ! wget -q "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"; then
      echo "Failed to download OpenSSL. Please check your internet connection."
      rm -rf "$SRC_DIR"
      exit 1
    fi
    
    tar -xzf "openssl-$OPENSSL_VERSION.tar.gz"
    cd "openssl-$OPENSSL_VERSION"
    
    # Build and install OpenSSL
    echo "Configuring OpenSSL..."
    if ! ./config --prefix="$OPENSSL_PREFIX" --openssldir="$OPENSSL_PREFIX" shared; then
      echo "OpenSSL configuration failed."
      rm -rf "$SRC_DIR"
      exit 1
    fi
    
    echo "Building OpenSSL..."
    if ! make clean; then
      echo "OpenSSL make clean failed."
      rm -rf "$SRC_DIR"
      exit 1
    fi
    
    if ! make -j$(nproc); then
      echo "OpenSSL build failed."
      rm -rf "$SRC_DIR"
      exit 1
    fi
    
    echo "Installing OpenSSL..."
    if ! make install_sw; then
      echo "OpenSSL installation failed."
      rm -rf "$SRC_DIR"
      exit 1
    fi
    
    if ! ldconfig; then
      echo "ldconfig failed."
      rm -rf "$SRC_DIR"
      exit 1
    fi
    
    # Clean up
    cd "$CLIENT_DIR"
    rm -rf "$SRC_DIR"
    
    # Verify installation
    if [ ! -d "$OPENSSL_PREFIX" ] || [ ! -f "$OPENSSL_PREFIX/lib/libssl.so" ]; then
      echo "OpenSSL installation verification failed."
      exit 1
    fi
    
    echo "OpenSSL $OPENSSL_VERSION has been installed to $OPENSSL_PREFIX"
  else
    echo "OpenSSL installation found at $OPENSSL_PREFIX"
  fi
}

# Install OpenSSL if needed
install_openssl

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