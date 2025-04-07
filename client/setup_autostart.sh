#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

# Get the absolute path to the rc4_client directory
CLIENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CLIENT_BINARY="$CLIENT_DIR/rc4_client"

# Ensure the binary exists and is executable
if [ ! -x "$CLIENT_BINARY" ]; then
  echo "Error: $CLIENT_BINARY not found or not executable"
  echo "Please compile the client first using the instructions in README.md"
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