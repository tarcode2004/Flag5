#!/bin/bash
set -euo pipefail

# Configuration
SERVICE_NAME="payload-rc4-line-server" # Changed name slightly to reflect purpose
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SERVER_SCRIPT="$SCRIPT_DIR/rc4_line_server.py" # Assumes modified script from above
DATA_FILE="$SCRIPT_DIR/data.txt"
INDEX_FILE="$SCRIPT_DIR/line_index.txt" # Added for completeness
CERT_DIR="$SCRIPT_DIR/certs"
# --- MODIFIED: Use system Python 3 ---
PYTHON_EXEC="python3" # Use system default Python 3
PIP_EXEC="$PYTHON_EXEC -m pip"       # Use python3 -m pip instead
# --- END MODIFIED ---

echo "[setup_server] Stopping conflicting services..."
# (Stop apache2, nginx, lsof checks remain the same as before)
# Stop and disable Apache if it's installed
if systemctl list-units --type=service | grep -q apache2; then
    sudo systemctl stop apache2
    sudo systemctl disable apache2
    echo "[setup_server] Stopped and disabled apache2."
fi
# Stop any other services using port 443
echo "[setup_server] Stopping any services using port 443..."
if ! command -v lsof &> /dev/null; then
    echo "[setup_server] Installing lsof..."
    sudo apt-get update
    sudo apt-get install -y lsof
fi
echo "[setup_server] Attempting to stop processes using port 443..."
PIDS=$(sudo lsof -ti:443 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    echo "[setup_server] Found PIDs using port 443: $PIDS. Stopping..."
    sudo kill -9 $PIDS || true
else
    echo "[setup_server] No processes found using port 443"
fi
# Additional checks for nginx and lighttpd
for svc in nginx lighttpd; do
    if systemctl list-units --type=service | grep -q "$svc"; then
        sudo systemctl stop "$svc"
        sudo systemctl disable "$svc"
        echo "[setup_server] Stopped and disabled $svc."
    fi
done
sleep 1
echo "[setup_server] Verifying port 443 is free..."
if sudo lsof -i:443; then
    echo "[setup_server] Error: Port 443 is still in use."
    exit 1
fi
echo "[setup_server] Port 443 is free."


echo "[setup_server] Installing dependencies..."
sudo apt-get update
sudo apt-get install -y \
    ${PYTHON_EXEC} \
    ${PIP_EXEC} \
    python3-pycryptodome # Package name might vary (e.g., python-pycryptodome) - install via pip if needed

# Verify python and pip exist
if ! command -v $PYTHON_EXEC &> /dev/null; then
    echo "[setup_server] Error: ${PYTHON_EXEC} not found after installation attempt."
    exit 1
fi
if ! command -v $PIP_EXEC &> /dev/null; then
    echo "[setup_server] Error: ${PIP_EXEC} not found. Trying to install python3-pip..."
    sudo apt-get install -y python3-pip || { echo "Failed to install pip3."; exit 1; }
fi

# Install pycryptodome via pip if the apt package wasn't found or didn't work
if ! $PYTHON_EXEC -c "import Crypto.Cipher.ARC4" &> /dev/null; then
   echo "[setup_server] Installing pycryptodome via pip..."
   sudo $PIP_EXEC install pycryptodome
   # Double check
   if ! $PYTHON_EXEC -c "import Crypto.Cipher.ARC4" &> /dev/null; then
      echo "[setup_server] Error: Failed to install pycryptodome."
      exit 1
   fi
fi

# --- REMOVED: Custom OpenSSL and Python build sections ---

echo "[setup_server] Creating SSL certificates..."
# (Certificate generation logic remains the same as before)
sudo mkdir -p "$CERT_DIR"
if [ ! -f "$CERT_DIR/server.crt" ] || [ ! -f "$CERT_DIR/server.key" ]; then
    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.crt" \
        -subj "/C=US/ST=CTFState/L=CTFCity/O=OmniTech/OU=AIDivision/CN=localhost" \
        -sha256
    sudo chmod 600 "$CERT_DIR/server.key"
    echo "[setup_server] Generated self-signed certificate."
else
    echo "[setup_server] Certificate files already exist."
fi

echo "[setup_server] Creating systemd service file..."
# --- MODIFIED: Use system python path and remove LD_LIBRARY_PATH ---
SYSTEM_PYTHON_PATH=$(command -v $PYTHON_EXEC)
if [ -z "$SYSTEM_PYTHON_PATH" ]; then
    echo "[setup_server] Error: Could not find path for $PYTHON_EXEC."
    exit 1
fi

sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null <<EOF
[Unit]
Description=Payload RC4 Line Server (Standard TLS)
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SYSTEM_PYTHON_PATH $SERVER_SCRIPT
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
# No custom LD_LIBRARY_PATH needed anymore

[Install]
WantedBy=multi-user.target
EOF
# --- END MODIFIED ---

echo "[setup_server] Setting up permissions..."
sudo chmod +x "$SERVER_SCRIPT"
# Ensure data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "[setup_server] WARNING: $DATA_FILE not found. Creating empty file."
    sudo touch "$DATA_FILE"
fi
sudo chmod 644 "$DATA_FILE" # Ensure server can read it
# Ensure index file exists and is writable by the server (root in this case)
sudo touch "$INDEX_FILE"
sudo chmod 644 "$INDEX_FILE"

echo "[setup_server] Enabling and starting service..."
sudo systemctl daemon-reload
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "[setup_server] Stopping existing service instance..."
    sudo systemctl stop "$SERVICE_NAME"
fi
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

sleep 2

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "[setup_server] Service '$SERVICE_NAME' started successfully!"
    echo "[setup_server] Server should be running on https://<your-server-ip>:443"
    echo "[setup_server] Use 'sudo systemctl status $SERVICE_NAME' or 'sudo journalctl -u $SERVICE_NAME -f' to check logs."
else
    echo "[setup_server] Error: Service '$SERVICE_NAME' failed to start. Check status with:"
    echo "sudo systemctl status $SERVICE_NAME"
    echo "sudo journalctl -u $SERVICE_NAME --no-pager -n 50"
    exit 1
fi

echo "[setup_server] Setup complete."