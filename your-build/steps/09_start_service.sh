#!/bin/bash
set -euo pipefail
APACHE_SERVICE_NAME="apache2-custom"
APACHE_PREFIX="/usr/local/apache2"
APACHE_LOG_DIR="$APACHE_PREFIX/logs"

echo "[09_start_service] Starting custom Apache server (HTTPS only)..."
sudo systemctl restart "$APACHE_SERVICE_NAME"
sleep 5
sudo systemctl status "$APACHE_SERVICE_NAME" --no-pager

# Verify HTTPS (443) is active
if ! sudo ss -tulnp | grep ':443.*httpd'; then
    echo "[!] Apache is not listening on port 443. Please check the logs."
    exit 1
fi

# Verify HTTP (80) is NOT active
if sudo ss -tulnp | grep ':80.*httpd'; then
    echo "[!] Apache is still listening on port 80. HTTPS-only configuration failed."
    exit 1
else
    echo "[09_start_service] Verified Apache is not listening on port 80 (HTTP disabled)"
fi
