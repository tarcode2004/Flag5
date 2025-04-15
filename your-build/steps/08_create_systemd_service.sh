#!/bin/bash
set -euo pipefail
APACHE_PREFIX="/usr/local/apache2"
APACHE_LOG_DIR="$APACHE_PREFIX/logs"
APACHE_SERVICE_NAME="apache2-custom"
OPENSSL_PREFIX="/usr/local/ssl"

echo "[08_create_systemd_service] Creating systemd service file..."
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${APACHE_SERVICE_NAME}.service"

# Ensure PID directory exists and has proper permissions
sudo mkdir -p "$APACHE_LOG_DIR"
sudo chown -R root:root "$APACHE_LOG_DIR"
sudo chmod 755 "$APACHE_LOG_DIR"
sudo touch "$APACHE_LOG_DIR/httpd.pid"
sudo chown root:root "$APACHE_LOG_DIR/httpd.pid"
sudo chmod 644 "$APACHE_LOG_DIR/httpd.pid"

sudo tee "$SYSTEMD_SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=The Apache HTTP Server (Custom Build with Old OpenSSL)
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
Environment=LD_LIBRARY_PATH=${OPENSSL_PREFIX}/lib
PIDFile=${APACHE_LOG_DIR}/httpd.pid
ExecStartPre=/bin/mkdir -p ${APACHE_LOG_DIR}
ExecStartPre=/bin/chown root:root ${APACHE_LOG_DIR}
ExecStartPre=/bin/chmod 755 ${APACHE_LOG_DIR}
ExecStartPre=/bin/touch ${APACHE_LOG_DIR}/httpd.pid
ExecStartPre=/bin/chown root:root ${APACHE_LOG_DIR}/httpd.pid
ExecStartPre=/bin/chmod 644 ${APACHE_LOG_DIR}/httpd.pid
ExecStart=${APACHE_PREFIX}/bin/apachectl -k start
ExecReload=${APACHE_PREFIX}/bin/apachectl graceful
ExecStop=${APACHE_PREFIX}/bin/apachectl -k stop
KillMode=process
Restart=on-failure
RestartSec=5s
PrivateTmp=true
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$APACHE_SERVICE_NAME"
