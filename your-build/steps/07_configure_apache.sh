#!/bin/bash
set -euo pipefail
APACHE_PREFIX="/usr/local/apache2"
APACHE_LOG_DIR="$APACHE_PREFIX/logs"
DOCUMENT_ROOT="$APACHE_PREFIX/htdocs"
HTTPD_CONF="$APACHE_PREFIX/conf/httpd.conf"
OPENSSL_PREFIX="/usr/local/ssl"

echo "[07_configure_apache] Configuring Apache for SSL only (no HTTP)..."

# Ensure the SSL module is loaded.
sudo sed -i 's/^#LoadModule ssl_module/LoadModule ssl_module/' "$HTTPD_CONF" || true

# Comment out the default port 80 Listen directive
sudo sed -i 's/^Listen 80/#Listen 80/' "$HTTPD_CONF"

# Create needed directories.
sudo mkdir -p "$DOCUMENT_ROOT" "$APACHE_LOG_DIR" "$APACHE_PREFIX/conf/extra" "$APACHE_PREFIX/conf/ssl"

# Write a test file.
CTF_DATE=$(date +"%B %d, %Y")
echo "OmniTech Satellite Uplink Status - $CTF_DATE
AI Control: Active
Uplink Data: 6f5b3e8c9d2a1f7e4b0c8d9e2f5a1b7c3d9e0f5a2b7c4d8e1f5a3b9c6d0e2f7
Security Notification: admin lacks brute-force protection." | sudo tee "$DOCUMENT_ROOT/satellite_uplink_status.txt" > /dev/null

# Generate a self-signed certificate.
SSL_CERT_DIR="$APACHE_PREFIX/conf/ssl"
SSL_KEY_FILE="$SSL_CERT_DIR/server.key"
SSL_CRT_FILE="$SSL_CERT_DIR/server.crt"
sudo "$OPENSSL_PREFIX/bin/openssl" req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout "$SSL_KEY_FILE" \
  -out "$SSL_CRT_FILE" \
  -subj "/C=US/ST=CTFState/L=CTFCity/O=OmniTech/OU=AIDivision/CN=localhost"
sudo chmod 600 "$SSL_KEY_FILE"

# Write the SSL configuration.
SSL_CONF_FILE="$APACHE_PREFIX/conf/extra/httpd-ssl.conf"
sudo tee "$SSL_CONF_FILE" > /dev/null <<EOF
Listen 443

<VirtualHost _default_:443>
    DocumentRoot "$DOCUMENT_ROOT"
    ServerName localhost

    ErrorLog "$APACHE_LOG_DIR/error_ssl_log"
    TransferLog "$APACHE_LOG_DIR/access_ssl_log"

    LogLevel ssl:info

    SSLEngine on
    SSLCertificateFile "$SSL_CRT_FILE"
    SSLCertificateKeyFile "$SSL_KEY_FILE"

    SSLCipherSuite RC4-SHA
    SSLProtocol all -SSLv3
    SSLHonorCipherOrder on

    <Files ~ "\.(cgi|shtml|phtml|php3?)$">
        SSLOptions +StdEnvVars
    </Files>
    <Directory "/usr/local/apache2/cgi-bin">
        SSLOptions +StdEnvVars
    </Directory>

    BrowserMatch "MSIE [2-5]" nokeepalive ssl-unclean-shutdown downgrade-1.0 force-response-1.0

    CustomLog "$APACHE_LOG_DIR/ssl_request_log" "%t %h %{SSL_PROTOCOL}x %{SSL_CIPHER}x \"%r\" %b"
</VirtualHost>
EOF

# Ensure the SSL config is included in the main configuration.
SSL_INCLUDE_LINE="Include conf/extra/httpd-ssl.conf"
if ! grep -q "^\s*${SSL_INCLUDE_LINE}" "$HTTPD_CONF"; then
    echo "${SSL_INCLUDE_LINE}" | sudo tee -a "$HTTPD_CONF" > /dev/null
fi

# Test Apache configuration.
sudo env LD_LIBRARY_PATH="$OPENSSL_PREFIX/lib" "$APACHE_PREFIX/bin/apachectl" configtest
