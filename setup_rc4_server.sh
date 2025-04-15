#!/bin/bash
set -euo pipefail

# Configuration
SERVICE_NAME="rc4-line-server"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SERVER_SCRIPT="$SCRIPT_DIR/rc4_line_server.py"
DATA_FILE="$SCRIPT_DIR/data.txt"
CERT_DIR="$SCRIPT_DIR/certs"

echo "[setup_rc4_server] Stopping conflicting services..."
# Stop and disable Apache if it's installed
if systemctl list-units --type=service | grep -q apache2; then
    sudo systemctl stop apache2
    sudo systemctl disable apache2
fi

# Stop any other services using port 443
echo "[setup_rc4_server] Stopping any services using port 443..."
# First check if lsof is installed
if ! command -v lsof &> /dev/null; then
    echo "[setup_rc4_server] Installing lsof..."
    sudo apt-get update
    sudo apt-get install -y lsof
fi

# Check what's using port 443
echo "[setup_rc4_server] Checking processes using port 443..."
sudo lsof -i:443 || true

# Try to stop any processes using port 443
echo "[setup_rc4_server] Attempting to stop processes using port 443..."
PIDS=$(sudo lsof -ti:443 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    echo "[setup_rc4_server] Found PIDs using port 443: $PIDS"
    for PID in $PIDS; do
        echo "[setup_rc4_server] Stopping process $PID..."
        sudo kill -9 "$PID" || true
    done
else
    echo "[setup_rc4_server] No processes found using port 443"
fi

# Additional check for nginx
if systemctl list-units --type=service | grep -q nginx; then
    sudo systemctl stop nginx
    sudo systemctl disable nginx
fi

# Additional check for lighttpd
if systemctl list-units --type=service | grep -q lighttpd; then
    sudo systemctl stop lighttpd
    sudo systemctl disable lighttpd
fi

# Verify port 443 is free
echo "[setup_rc4_server] Verifying port 443 is free..."
if sudo lsof -i:443; then
    echo "[setup_rc4_server] Error: Port 443 is still in use after stopping services"
    exit 1
else
    echo "[setup_rc4_server] Port 443 is free"
fi

echo "[setup_rc4_server] Installing dependencies..."
# Install Python and required packages
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv python3-cryptography

# Install pycryptodome in the system Python environment
sudo pip3 install --break-system-packages pycryptodome

echo "[setup_rc4_server] Creating SSL certificates..."
# Create certs directory if it doesn't exist
sudo mkdir -p "$CERT_DIR"

# Generate self-signed certificate if it doesn't exist
if [ ! -f "$CERT_DIR/server.crt" ] || [ ! -f "$CERT_DIR/server.key" ]; then
    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.crt" \
        -subj "/C=US/ST=CTFState/L=CTFCity/O=OmniTech/OU=AIDivision/CN=localhost"
    sudo chmod 600 "$CERT_DIR/server.key"
fi

echo "[setup_rc4_server] Creating systemd service..."
# Create systemd service file
sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null <<EOF
[Unit]
Description=RC4 Line Server
After=network.target

[Service]
Type=simple
User=root
Group=root
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
sudo chmod +x "$SERVER_SCRIPT"

# Create line index file if it doesn't exist
sudo touch "$SCRIPT_DIR/line_index.txt"
sudo chmod 644 "$SCRIPT_DIR/line_index.txt"

echo "[setup_rc4_server] Enabling and starting service..."
# Reload systemd and enable/start the service
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

# Check service status
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "[setup_rc4_server] Service started successfully!"
    echo "[setup_rc4_server] Server is running on https://localhost:443"
else
    echo "[setup_rc4_server] Error: Service failed to start. Check status with:"
    echo "sudo systemctl status $SERVICE_NAME"
    exit 1
fi 