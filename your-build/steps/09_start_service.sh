#!/bin/bash
set -euo pipefail
APACHE_SERVICE_NAME="apache2-custom"
APACHE_PREFIX="/usr/local/apache2"
APACHE_LOG_DIR="$APACHE_PREFIX/logs"

echo "[09_start_service] Starting custom Apache server..."
sudo systemctl restart "$APACHE_SERVICE_NAME"
sleep 5
sudo systemctl status "$APACHE_SERVICE_NAME" --no-pager

if ! sudo ss -tulnp | grep ':443.*httpd'; then
    echo "[!] Apache is not listening on port 443. Please check the logs."
    exit 1
fi
