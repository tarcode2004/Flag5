#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

# --- START MODIFICATION ---
# Define the path for the SSL Key Log file
# --- USER: You can change this path ---
# Example for user 'ubuntu' desktop: /home/ubuntu/Desktop/sslkeylog.log
# Example for root user desktop: /root/Desktop/sslkeylog.log
# Defaulting to /tmp/ for general accessibility.
# Ensure the service (runs as root by default) has write permissions to this location.
KEYLOG_FILE_PATH="/tmp/sslkeylog.log"
echo ">>> SSL Key Log file will be saved to: $KEYLOG_FILE_PATH" # Inform the user
# --- END MODIFICATION ---


# Get the absolute path to the rc4_client directory
CLIENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CLIENT_BINARY="$CLIENT_DIR/rc4_client"
CLIENT_SOURCE="$CLIENT_DIR/rc4_client.c"

# Check and install prerequisites
check_install_prerequisites() {
  echo "Checking for build prerequisites..."
  # Check for make, gcc, wget first as they are essential for building OpenSSL
  if ! command -v make &>/dev/null || ! command -v gcc &>/dev/null || ! command -v wget &>/dev/null; then
    echo "Installing essential build dependencies (make, gcc, wget)..."
    apt-get update
    apt-get install -y make gcc wget
    if [ $? -ne 0 ]; then
      echo "Failed to install essential build dependencies. Exiting."
      exit 1
    fi
  fi
  # Check for other dependencies needed by OpenSSL config/build or client compilation
  if ! dpkg -s build-essential libpcre3-dev zlib1g-dev libtool curl libexpat1-dev &>/dev/null; then
      echo "Installing remaining build dependencies..."
      apt-get update
      apt-get install -y build-essential libpcre3-dev zlib1g-dev libtool curl libexpat1-dev
      if [ $? -ne 0 ]; then
          echo "Failed to install remaining build dependencies. Exiting."
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
    echo "Downloading OpenSSL..."
    if ! wget -q "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"; then
      echo "Failed to download OpenSSL. Please check your internet connection."
      rm -rf "$SRC_DIR"
      exit 1
    fi

    tar -xzf "openssl-$OPENSSL_VERSION.tar.gz"
    cd "openssl-$OPENSSL_VERSION"

    # Build and install OpenSSL
    echo "Configuring OpenSSL..."
    # Added 'no-async' as it can cause issues on some systems with 1.0.2
    if ! ./config --prefix="$OPENSSL_PREFIX" --openssldir="$OPENSSL_PREFIX" shared no-async; then
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

    # Use -j N based on processor cores for faster build
    BUILD_JOBS=$(nproc)
    echo "Building with $BUILD_JOBS jobs..."
    if ! make -j$BUILD_JOBS; then
      echo "OpenSSL build failed."
      rm -rf "$SRC_DIR"
      exit 1
    fi

    echo "Installing OpenSSL..."
    # Use install_sw to avoid installing man pages, install_ssldirs for dirs
    if ! make install_sw; then
      echo "OpenSSL software installation failed."
      rm -rf "$SRC_DIR"
      exit 1
    fi
     if ! make install_ssldirs; then
       echo "OpenSSL ssldirs installation failed."
       rm -rf "$SRC_DIR"
       exit 1
     fi


    # Update linker cache - ensure the path is considered
    echo "$OPENSSL_PREFIX/lib" > /etc/ld.so.conf.d/openssl-102u.conf
    if ! ldconfig; then
      echo "ldconfig failed."
      # Attempt cleanup even if ldconfig fails
      rm -f /etc/ld.so.conf.d/openssl-102u.conf
      ldconfig # Try reverting
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
    # Ensure linker path is configured even if OpenSSL was already installed
    if [ ! -f /etc/ld.so.conf.d/openssl-102u.conf ] || ! grep -q "$OPENSSL_PREFIX/lib" /etc/ld.so.conf.d/openssl-102u.conf; then
       echo "$OPENSSL_PREFIX/lib" > /etc/ld.so.conf.d/openssl-102u.conf
       ldconfig
       echo "Updated linker cache for existing OpenSSL."
    fi
  fi
}

# Install OpenSSL if needed
install_openssl

# Compile the client if source exists and binary doesn't exist or needs recompilation
if [ -f "$CLIENT_SOURCE" ]; then
  if [ ! -x "$CLIENT_BINARY" ] || [ "$CLIENT_SOURCE" -nt "$CLIENT_BINARY" ]; then
    echo "Compiling rc4_client..."
    # Explicitly point to the custom OpenSSL library path for linking
    gcc "$CLIENT_SOURCE" -o "$CLIENT_BINARY" \
      -I"$OPENSSL_PREFIX/include" \
      -L"$OPENSSL_PREFIX/lib" \
      -Wl,-rpath,"$OPENSSL_PREFIX/lib" \
      -lssl -lcrypto -ldl -pthread

    if [ $? -eq 0 ]; then
      echo "Compilation successful"
      chmod +x "$CLIENT_BINARY"
    else
      echo "Error: Compilation failed"
      exit 1
    fi
  else
    echo "Binary $CLIENT_BINARY already exists and is up to date"
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
# Use the KEYLOG_FILE_PATH variable defined earlier
echo "Creating systemd service file..."
cat > /etc/systemd/system/rc4-client.service << EOF
[Unit]
Description=RC4 Client Service making requests for CTF
After=network.target

[Service]
Type=simple
# Set LD_LIBRARY_PATH for custom OpenSSL and SSLKEYLOGFILE for decryption
Environment="LD_LIBRARY_PATH=$OPENSSL_PREFIX/lib:\$LD_LIBRARY_PATH"
Environment="SSLKEYLOGFILE=$KEYLOG_FILE_PATH"
# The service (running as root by default) needs write permission to $KEYLOG_FILE_PATH
# If using a non-default path (like a user's desktop), ensure permissions are correct
# or consider using the User= directive (e.g., User=ctfplayer) if applicable.
WorkingDirectory=$CLIENT_DIR
ExecStart=$CLIENT_BINARY
Restart=always
# Reduce restart frequency slightly
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable and (re)start the service
echo "Reloading systemd daemon..."
systemctl daemon-reload
echo "Enabling rc4-client service..."
systemctl enable rc4-client.service
echo "Restarting rc4-client service..."
# Use restart instead of start to ensure changes are applied if service was already running
systemctl restart rc4-client.service

echo "RC4 client setup complete. Service enabled and started."
echo "SSL Key Log file is configured to be saved at: $KEYLOG_FILE_PATH"
echo "Use 'journalctl -u rc4-client.service -f' to follow service logs."
echo "Use 'systemctl status rc4-client.service' to check current status."