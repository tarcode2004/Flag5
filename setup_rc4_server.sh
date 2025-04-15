#!/bin/bash
set -euo pipefail

# Configuration
SERVICE_NAME="rc4-line-server"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SERVER_SCRIPT="$SCRIPT_DIR/rc4_line_server.py"
DATA_FILE="$SCRIPT_DIR/data.txt"
CERT_DIR="$SCRIPT_DIR/certs"
PYTHON_VERSION="3.12.4"
PYTHON_SRC_DIR="$SCRIPT_DIR/Python-$PYTHON_VERSION"
PYTHON_INSTALL_DIR="/opt/python-custom"
OPENSSL_DIR="/usr/local/ssl"

echo "[setup_rc4_server] Stopping conflicting services..."
# Stop and disable Apache if it's installed
if systemctl list-units --type=service | grep -q apache2; then
    sudo systemctl stop apache2
    sudo systemctl disable apache2
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
    libssl-dev

echo "[setup_rc4_server] Downloading and extracting Python $PYTHON_VERSION..."
cd "$SCRIPT_DIR"
if [ ! -f "Python-$PYTHON_VERSION.tgz" ]; then
    wget "https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz"
fi
tar -xzf "Python-$PYTHON_VERSION.tgz"

echo "[setup_rc4_server] Building Python $PYTHON_VERSION with custom OpenSSL..."
cd "$PYTHON_SRC_DIR"
export CPPFLAGS="-I$OPENSSL_DIR/include"
export LDFLAGS="-L$OPENSSL_DIR/lib"
export LD_LIBRARY_PATH="$OPENSSL_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="$OPENSSL_DIR/lib/pkgconfig"

./configure \
    --prefix="$PYTHON_INSTALL_DIR" \
    --with-openssl="$OPENSSL_DIR" \
    --with-openssl-rpath=auto \
    --enable-optimizations

make -j"$(nproc)" || {
    echo "[setup_rc4_server] Initial make failed, trying full clean rebuild..."
    make clean
    ./configure \
        --prefix="$PYTHON_INSTALL_DIR" \
        --with-openssl="$OPENSSL_DIR" \
        --with-openssl-rpath=auto \
        --enable-optimizations
    make -j"$(nproc)"
}

sudo make altinstall

echo "[setup_rc4_server] Verifying Python installation has working SSL..."
if ! "$PYTHON_INSTALL_DIR/bin/python3.12" -c "import ssl; print(ssl.OPENSSL_VERSION)"; then
    echo "[setup_rc4_server] Error: _ssl module not built. Check OpenSSL paths and rebuild."
    exit 1
fi


echo "[setup_rc4_server] Installing Python packages..."
"$PYTHON_INSTALL_DIR/bin/pip3.12" install pycryptodome

echo "[setup_rc4_server] Creating SSL certificates..."
sudo mkdir -p "$CERT_DIR"
if [ ! -f "$CERT_DIR/server.crt" ] || [ ! -f "$CERT_DIR/server.key" ]; then
    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.crt" \
        -subj "/C=US/ST=CTFState/L=CTFCity/O=OmniTech/OU=AIDivision/CN=localhost"
    sudo chmod 600 "$CERT_DIR/server.key"
fi

echo "[setup_rc4_server] Creating systemd service..."
sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null <<EOF
[Unit]
Description=RC4 Line Server
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=$PYTHON_INSTALL_DIR/bin/python3.12 $SERVER_SCRIPT
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

echo "[setup_rc4_server] Setting up permissions..."
sudo chmod +x "$SERVER_SCRIPT"
sudo touch "$SCRIPT_DIR/line_index.txt"
sudo chmod 644 "$SCRIPT_DIR/line_index.txt"

echo "[setup_rc4_server] Enabling and starting service..."
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "[setup_rc4_server] Service started successfully!"
    echo "[setup_rc4_server] Server is running on https://localhost:443"
else
    echo "[setup_rc4_server] Error: Service failed to start. Check status with:"
    echo "sudo systemctl status $SERVICE_NAME"
    exit 1
fi