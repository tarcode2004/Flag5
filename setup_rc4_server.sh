#!/bin/bash
set -euo pipefail

# Configuration
SERVICE_NAME="rc4-line-server"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SERVER_SCRIPT="$SCRIPT_DIR/rc4_line_server.py"
DATA_FILE="$SCRIPT_DIR/data.txt"
CERT_DIR="$SCRIPT_DIR/certs"
# --- MODIFIED: Use Python 3.9 ---
PYTHON_VERSION="3.9.19" # Changed from 3.12.4
PYTHON_EXEC="python3.9"  # Executable name after altinstall
PIP_EXEC="pip3.9"      # Pip executable name
# --- END MODIFIED ---
PYTHON_SRC_DIR="$SCRIPT_DIR/Python-$PYTHON_VERSION"
PYTHON_INSTALL_DIR="/opt/python-custom" # Keep install dir distinct
OPENSSL_DIR="/usr/local/ssl" # Path where OpenSSL 1.0.2u is installed

echo "[setup_rc4_server] Stopping conflicting services..."
# Stop and disable Apache if it's installed
if systemctl list-units --type=service | grep -q apache2; then
    sudo systemctl stop apache2
    sudo systemctl disable apache2
    echo "[setup_rc4_server] Stopped and disabled apache2."
fi

# Stop any other services using port 443
echo "[setup_rc4_server] Stopping any services using port 443..."
if ! command -v lsof &> /dev/null; then
    echo "[setup_rc4_server] Installing lsof..."
    sudo apt-get update
    sudo apt-get install -y lsof
fi

echo "[setup_rc4_server] Checking processes using port 443..."
sudo lsof -i:443 || true

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

# Additional checks for nginx and lighttpd
for svc in nginx lighttpd; do
    if systemctl list-units --type=service | grep -q "$svc"; then
        sudo systemctl stop "$svc"
        sudo systemctl disable "$svc"
        echo "[setup_rc4_server] Stopped and disabled $svc."
    fi
done

echo "[setup_rc4_server] Verifying port 443 is free..."
if sudo lsof -i:443; then
    echo "[setup_rc4_server] Error: Port 443 is still in use after stopping services"
    exit 1
else
    echo "[setup_rc4_server] Port 443 is free"
fi

echo "[setup_rc4_server] Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    zlib1g-dev \
    libncurses5-dev \
    libgdbm-dev \
    libnss3-dev \
    libreadline-dev \
    libffi-dev \
    wget \
    libbz2-dev \
    libsqlite3-dev \
    lzma-dev \
    uuid-dev \
    tk-dev \
    libssl-dev # Keep this for other potential builds, though we override OpenSSL for Python

echo "[setup_rc4_server] Downloading and extracting Python $PYTHON_VERSION..."
cd "$SCRIPT_DIR"
if [ ! -f "Python-$PYTHON_VERSION.tgz" ]; then
    # --- MODIFIED: Use Python 3.9 URL ---
    wget "https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz"
    # --- END MODIFIED ---
fi
# Clean previous source dir if exists
if [ -d "$PYTHON_SRC_DIR" ]; then
    echo "[setup_rc4_server] Removing existing source directory $PYTHON_SRC_DIR..."
    rm -rf "$PYTHON_SRC_DIR"
fi
tar -xzf "Python-$PYTHON_VERSION.tgz"

echo "[setup_rc4_server] Building Python $PYTHON_VERSION with custom OpenSSL ($OPENSSL_DIR)..."
cd "$PYTHON_SRC_DIR"

# Explicitly ensure custom OpenSSL is found for build and runtime
export CPPFLAGS="-I$OPENSSL_DIR/include"
export LDFLAGS="-L$OPENSSL_DIR/lib -Wl,-rpath,$OPENSSL_DIR/lib" # Add rpath during linking
export LD_LIBRARY_PATH="$OPENSSL_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" # For build process tools if needed
export PKG_CONFIG_PATH="$OPENSSL_DIR/lib/pkgconfig"

echo "[setup_rc4_server] Configuring Python $PYTHON_VERSION..."
./configure \
    --prefix="$PYTHON_INSTALL_DIR" \
    --with-openssl="$OPENSSL_DIR" \
    --with-openssl-rpath=auto \
    --enable-optimizations \
    --with-ensurepip=install # Ensure pip is installed

echo "[setup_rc4_server] Building Python $PYTHON_VERSION (make)..."
make -j"$(nproc)" || {
    echo "[setup_rc4_server] Initial make failed, trying full clean rebuild..."
    make clean

    # Re-export vars just in case
    export CPPFLAGS="-I$OPENSSL_DIR/include"
    export LDFLAGS="-L$OPENSSL_DIR/lib -Wl,-rpath,$OPENSSL_DIR/lib"
    export LD_LIBRARY_PATH="$OPENSSL_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export PKG_CONFIG_PATH="$OPENSSL_DIR/lib/pkgconfig"

    ./configure \
        --prefix="$PYTHON_INSTALL_DIR" \
        --with-openssl="$OPENSSL_DIR" \
        --with-openssl-rpath=auto \
        --enable-optimizations \
        --with-ensurepip=install

    make -j"$(nproc)"
}

echo "[setup_rc4_server] Installing Python $PYTHON_VERSION (make altinstall)..."
# Use altinstall to avoid overwriting system python3
sudo make altinstall

echo "[setup_rc4_server] Verifying Python installation has working SSL..."
# --- MODIFIED: Use python3.9 executable ---
PYTHON_BIN="$PYTHON_INSTALL_DIR/bin/$PYTHON_EXEC"
if [ ! -x "$PYTHON_BIN" ]; then
    echo "[setup_rc4_server] Error: Python executable $PYTHON_BIN not found after installation!"
    exit 1
fi

if ! "$PYTHON_BIN" -c "import ssl; print(f'SSL Module OK. OpenSSL Version linked: {ssl.OPENSSL_VERSION}')"; then
    echo "[setup_rc4_server] Error: Failed to import ssl module or print OpenSSL version."
    echo "[setup_rc4_server] Check OpenSSL paths ($OPENSSL_DIR), build logs in $PYTHON_SRC_DIR, and ensure OpenSSL 1.0.2 build succeeded."
    exit 1
else
     echo "[setup_rc4_server] Python SSL check successful."
fi
# --- END MODIFIED ---


echo "[setup_rc4_server] Installing Python packages..."
# --- MODIFIED: Use pip3.9 executable ---
PIP_BIN="$PYTHON_INSTALL_DIR/bin/$PIP_EXEC"
if [ ! -x "$PIP_BIN" ]; then
    echo "[setup_rc4_server] Error: Pip executable $PIP_BIN not found!"
    # Attempt to bootstrap pip if configure didn't install it
    "$PYTHON_BIN" -m ensurepip --upgrade || true
    if [ ! -x "$PIP_BIN" ]; then
       echo "[setup_rc4_server] Still cannot find $PIP_BIN. Check Python installation."
       exit 1
    fi
fi
"$PIP_BIN" install --upgrade pip # Upgrade pip itself first
"$PIP_BIN" install pycryptodome
# --- END MODIFIED ---

echo "[setup_rc4_server] Creating SSL certificates..."
sudo mkdir -p "$CERT_DIR"
if [ ! -f "$CERT_DIR/server.crt" ] || [ ! -f "$CERT_DIR/server.key" ]; then
    # Using SHA256 for signature, although client uses RC4 for bulk encryption
    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.crt" \
        -subj "/C=US/ST=CTFState/L=CTFCity/O=OmniTech/OU=AIDivision/CN=localhost" \
        -sha256
    sudo chmod 600 "$CERT_DIR/server.key"
    echo "[setup_rc4_server] Generated self-signed certificate."
else
    echo "[setup_rc4_server] Certificate files already exist."
fi

echo "[setup_rc4_server] Creating systemd service file..."
# --- MODIFIED: Use correct python3.9 path in ExecStart ---
sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null <<EOF
[Unit]
Description=RC4 Line Server (Python $PYTHON_VERSION)
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=$PYTHON_BIN $SERVER_SCRIPT
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
# Ensure the custom OpenSSL library is findable at runtime if rpath didn't work
Environment=LD_LIBRARY_PATH=$OPENSSL_DIR/lib

[Install]
WantedBy=multi-user.target
EOF
# --- END MODIFIED ---

echo "[setup_rc4_server] Setting up permissions..."
sudo chmod +x "$SERVER_SCRIPT"
# Ensure data file exists (needed by server script)
if [ ! -f "$DATA_FILE" ]; then
    echo "[setup_rc4_server] WARNING: $DATA_FILE not found. Creating empty file."
    sudo touch "$DATA_FILE"
    sudo chmod 644 "$DATA_FILE"
fi
# Ensure index file exists and has correct permissions
sudo touch "$SCRIPT_DIR/line_index.txt"
sudo chmod 644 "$SCRIPT_DIR/line_index.txt" # Server needs to read/write this

echo "[setup_rc4_server] Enabling and starting service..."
sudo systemctl daemon-reload
# Stop potentially running old instance before enabling/starting
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "[setup_rc4_server] Stopping existing service instance..."
    sudo systemctl stop "$SERVICE_NAME"
fi
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

sleep 2 # Give service time to start

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "[setup_rc4_server] Service '$SERVICE_NAME' started successfully!"
    echo "[setup_rc4_server] Server should be running on https://<your-server-ip>:443"
    echo "[setup_rc4_server] Use 'sudo systemctl status $SERVICE_NAME' or 'sudo journalctl -u $SERVICE_NAME -f' to check logs."
else
    echo "[setup_rc4_server] Error: Service '$SERVICE_NAME' failed to start. Check status with:"
    echo "sudo systemctl status $SERVICE_NAME"
    echo "sudo journalctl -u $SERVICE_NAME --no-pager -n 50"
    exit 1
fi

echo "[setup_rc4_server] Setup complete."