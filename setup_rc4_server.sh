#!/bin/bash
set -euo pipefail

# Configuration
SERVICE_NAME="rc4-line-server"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SERVER_SCRIPT="$SCRIPT_DIR/rc4_line_server.py"
DATA_FILE="$SCRIPT_DIR/data.txt"
CERT_DIR="$SCRIPT_DIR/certs"

echo "[setup_rc4_server] Installing dependencies..."
# Install Python and pip if not already installed
if ! command -v python3 &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip
fi

# Install required Python packages
sudo pip3 install pycryptodome

echo "[setup_rc4_server] Creating SSL certificates..."
# Create certs directory if it doesn't exist
mkdir -p "$CERT_DIR"

# Generate self-signed certificate if it doesn't exist
if [ ! -f "$CERT_DIR/server.crt" ] || [ ! -f "$CERT_DIR/server.key" ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.crt" \
        -subj "/C=US/ST=CTFState/L=CTFCity/O=OmniTech/OU=AIDivision/CN=localhost"
    chmod 600 "$CERT_DIR/server.key"
fi

echo "[setup_rc4_server] Creating systemd service..."
# Create systemd service file
sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null <<EOF
[Unit]
Description=RC4 Line Server
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$SCRIPT_DIR
ExecStart=/usr/bin/python3 $SERVER_SCRIPT
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

echo "[setup_rc4_server] Setting up permissions..."
# Ensure the server script is executable
chmod +x "$SERVER_SCRIPT"

# Create line index file if it doesn't exist
touch "$SCRIPT_DIR/line_index.txt"
chmod 644 "$SCRIPT_DIR/line_index.txt"

echo "[setup_rc4_server] Enabling and starting service..."
# Reload systemd and enable/start the service
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

# Check service status
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "[setup_rc4_server] Service started successfully!"
    echo "[setup_rc4_server] Server is running on https://localhost:8443"
else
    echo "[setup_rc4_server] Error: Service failed to start. Check status with:"
    echo "sudo systemctl status $SERVICE_NAME"
    exit 1
fi 