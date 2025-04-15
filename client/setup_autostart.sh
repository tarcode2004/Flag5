#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

# --- START MODIFICATION ---
# Define the path for the SSL Key Log file
# Ensure the directory exists and the service (running as root) can write here.
# /tmp/ is usually safe. For Desktop, ensure correct user/path.
KEYLOG_FILE_PATH="/tmp/sslkeylog.log"
KEYLOG_DIR=$(dirname "$KEYLOG_FILE_PATH")
mkdir -p "$KEYLOG_DIR" # Ensure directory exists
touch "$KEYLOG_FILE_PATH" # Create the file
chmod 644 "$KEYLOG_FILE_PATH" # Ensure it's writable by the service user (root)
echo ">>> SSL Key Log file will be saved to: $KEYLOG_FILE_PATH" # Inform the user
# --- END MODIFICATION ---

# Get the absolute path to the rc4_client directory
CLIENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CLIENT_BINARY="$CLIENT_DIR/rc4_client"
CLIENT_SOURCE="$CLIENT_DIR/rc4_client.c"

# Check and install prerequisites (Compiler and SSL Dev Libraries)
check_install_prerequisites() {
  echo "Checking for build prerequisites..."
  # Need build tools and standard OpenSSL development files
  if ! command -v gcc &>/dev/null || ! dpkg -s build-essential libssl-dev &>/dev/null; then
    echo "Installing build dependencies (gcc, build-essential, libssl-dev)..."
    apt-get update
    apt-get install -y gcc build-essential libssl-dev
    if [ $? -ne 0 ]; then
      echo "Failed to install build dependencies. Exiting."
      exit 1
    fi
    echo "Build dependencies installed successfully."
  else
    echo "Build dependencies already installed."
  fi
}

# --- REMOVED: Custom OpenSSL installation function ---
# install_openssl() { ... }

# Install prerequisites
check_install_prerequisites

# Compile the client using system OpenSSL
if [ -f "$CLIENT_SOURCE" ]; then
  # Recompile if binary doesn't exist or source is newer
  if [ ! -x "$CLIENT_BINARY" ] || [ "$CLIENT_SOURCE" -nt "$CLIENT_BINARY" ]; then
    echo "Compiling rc4_client using system OpenSSL..."
    # --- MODIFIED: Simplified compile command ---
    gcc "$CLIENT_SOURCE" -o "$CLIENT_BINARY" -lssl -lcrypto -ldl -pthread

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
echo "Creating systemd service file..."
# --- MODIFIED: Removed LD_LIBRARY_PATH, kept SSLKEYLOGFILE ---
cat > /etc/systemd/system/rc4-client.service << EOF
[Unit]
Description=RC4 Payload Client Service (Standard TLS)
After=network.target

[Service]
Type=simple
# Set SSLKEYLOGFILE for decryption via Wireshark
Environment="SSLKEYLOGFILE=$KEYLOG_FILE_PATH"
# Ensure the service (running as root) has write permission to $KEYLOG_FILE_PATH
WorkingDirectory=$CLIENT_DIR
ExecStart=$CLIENT_BINARY
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
# --- END MODIFIED ---

# Reload systemd, enable and (re)start the service
echo "Reloading systemd daemon..."
systemctl daemon-reload
echo "Enabling rc4-client service..."
systemctl enable rc4-client.service
echo "Restarting rc4-client service..."
systemctl restart rc4-client.service

echo "RC4 client setup complete. Service enabled and started."
echo "SSL Key Log file is configured to be saved at: $KEYLOG_FILE_PATH"
echo "Use 'journalctl -u rc4-client.service -f' to follow service logs."
echo "Use 'systemctl status rc4-client.service' to check current status."