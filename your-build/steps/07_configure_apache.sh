#!/bin/bash
set -euo pipefail
APACHE_PREFIX="/usr/local/apache2"
APACHE_LOG_DIR="$APACHE_PREFIX/logs"
DOCUMENT_ROOT="$APACHE_PREFIX/htdocs"
HTTPD_CONF="$APACHE_PREFIX/conf/httpd.conf"
OPENSSL_PREFIX="/usr/local/ssl"

echo "[07_configure_apache] Configuring Apache for SSL only (no HTTP) and PHP..."

# --- NEW: Switch Apache MPM to prefork for non-ZTS PHP compatibility ---
echo "[07_configure_apache] Switching Apache MPM to prefork..."
# Disable threaded MPMs (worker/event) - ignore errors if they aren't enabled
sudo a2dismod mpm_event mpm_worker || true
# Enable the non-threaded prefork MPM
sudo a2enmod mpm_prefork || { echo "Error: Failed to enable mpm_prefork. PHP might be unstable."; exit 1; }
# --- END NEW ---

# --- NEW: Install PHP Apache Module ---
echo "[07_configure_apache] Installing Apache PHP module..."
# Function to wait for package manager to be available
wait_for_package_manager() {
    local max_attempts=5
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if ! lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
            return 0
        fi
        echo "Waiting for package manager to be available (attempt $attempt/$max_attempts)..."
        sleep 5
        attempt=$((attempt + 1))
    done
    return 1
}

# Wait for package manager to be available
if wait_for_package_manager; then
    sudo apt-get update
    # Attempt to install PHP module - adjust package name if needed for your distribution
    sudo apt-get install -y libapache2-mod-php php || { 
        echo "Warning: PHP installation failed, proceeding anyway."; 
        # Clean up any stale locks
        sudo rm -f /var/lib/dpkg/lock-frontend
        sudo rm -f /var/lib/apt/lists/lock
        sudo rm -f /var/cache/apt/archives/lock
    }
else
    echo "Warning: Could not acquire package manager lock after multiple attempts, proceeding without PHP."
fi
# --- END NEW ---

# Ensure the SSL module is loaded.
sudo sed -i 's/^#LoadModule ssl_module/LoadModule ssl_module/' "$HTTPD_CONF" || true

# --- NEW: Ensure PHP module is loaded in httpd.conf ---
# Add PHP module loading if not present (adjust path if PHP installed differently)
PHP_MODULE_PATH=$(find /usr/lib/apache2/modules/ -name 'libphp*.so' | head -n 1)
if [ -n "$PHP_MODULE_PATH" ] && ! grep -q "LoadModule php_module" "$HTTPD_CONF" && ! grep -q "LoadModule php7_module" "$HTTPD_CONF" && ! grep -q "LoadModule php8_module" "$HTTPD_CONF"; then
    echo "LoadModule php_module $PHP_MODULE_PATH" | sudo tee -a "$HTTPD_CONF"
    echo "<FilesMatch \.php$>
    SetHandler application/x-httpd-php
</FilesMatch>" | sudo tee -a "$HTTPD_CONF"
fi
# --- END NEW ---

# Comment out the default port 80 Listen directive
sudo sed -i 's/^Listen 80/#Listen 80/' "$HTTPD_CONF"

# Create needed directories.
sudo mkdir -p "$DOCUMENT_ROOT" "$APACHE_LOG_DIR" "$APACHE_PREFIX/conf/extra" "$APACHE_PREFIX/conf/ssl"

# --- MODIFIED: Write the multi-line data file ---
echo "[07_configure_apache] Creating multi-line data file..."
CTF_DATE=$(date +"%B %d, %Y")
# Example: Put FLAG on line 2
echo "OmniTech Satellite Uplink Status - $CTF_DATE
FLAG{RC4_Keystream_Reused_Successfully_12345}
AI Control: Active
Uplink Data: 6f5b3e8c9d2a1f7e4b0c8d9e2f5a1b7c3d9e0f5a2b7c4d8e1f5a3b9c6d0e2f7
Security Notification: admin lacks brute-force protection." | sudo tee "$DOCUMENT_ROOT/real_satellite_data.txt" > /dev/null
# --- END MODIFIED ---

# --- NEW: Write the PHP handler script ---
echo "[07_configure_apache] Creating PHP handler script..."
sudo tee "$DOCUMENT_ROOT/satellite_uplink_status.php" > /dev/null <<'EOF'
<?php
header("Content-Type: text/plain"); // Ensure browser doesn't interpret as HTML

$counter_file = "/tmp/line_index.txt"; // Counter file in /tmp
$data_file = __DIR__ . "/real_satellite_data.txt"; // Data file in the same directory

// Check if data file exists
if (!file_exists($data_file)) {
    http_response_code(500);
    echo "Error: Data file not found.";
    exit;
}

// Read all lines from the data file
$file_lines = file($data_file, FILE_IGNORE_NEW_LINES);
if ($file_lines === false || count($file_lines) === 0) {
    http_response_code(500);
    echo "Error: Cannot read data file or file is empty.";
    exit;
}

// Get current index, default to 0 if counter file doesn't exist or is invalid
$index = 0;
if (file_exists($counter_file)) {
    $index = (int)file_get_contents($counter_file);
    // Validate index range
    if ($index < 0 || $index >= count($file_lines)) {
        $index = 0; // Reset if out of bounds
    }
}

// Output the line corresponding to the current index
echo $file_lines[$index] . "\n"; // Add newline back

// Increment index for the next request, wrap around if needed
$next_index = ($index + 1) % count($file_lines);

// Update the counter file
// Use error suppression (@) in case of permission issues, though /tmp should be writable
@file_put_contents($counter_file, $next_index);

?>
EOF
# Ensure apache user can write to the counter file (needed if /tmp has strict perms)
# sudo touch /tmp/line_index.txt
# sudo chown www-data:www-data /tmp/line_index.txt # Adjust user/group if different
# --- END NEW ---


# Generate a self-signed certificate.
SSL_CERT_DIR="$APACHE_PREFIX/conf/ssl"
SSL_KEY_FILE="$SSL_CERT_DIR/server.key"
SSL_CRT_FILE="$SSL_CERT_DIR/server.crt"
TEMP_SSL_CONF="/tmp/openssl.cnf"

# Create temporary OpenSSL configuration
cat > "$TEMP_SSL_CONF" << 'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = CTFState
L = CTFCity
O = OmniTech
OU = AIDivision
CN = localhost

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
EOF

# Always regenerate certificates to ensure proper configuration
echo "[07_configure_apache] Generating self-signed certificate..."
sudo rm -f "$SSL_KEY_FILE" "$SSL_CRT_FILE"
sudo "$OPENSSL_PREFIX/bin/openssl" req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout "$SSL_KEY_FILE" \
  -out "$SSL_CRT_FILE" \
  -config "$TEMP_SSL_CONF" \
  -extensions v3_req
sudo chmod 600 "$SSL_KEY_FILE"

# Clean up temporary config
rm -f "$TEMP_SSL_CONF"

# Verify the certificate is properly configured
if ! sudo "$OPENSSL_PREFIX/bin/openssl" x509 -in "$SSL_CRT_FILE" -text -noout | grep -q "CA:FALSE"; then
    echo "[!] Certificate verification failed. Please check the certificate configuration."
    exit 1
fi

# Write the SSL configuration.
SSL_CONF_FILE="$APACHE_PREFIX/conf/extra/httpd-ssl.conf"
sudo tee "$SSL_CONF_FILE" > /dev/null <<EOF
Listen 443

# Global SSL session cache settings
SSLSessionCache none
SSLSessionTickets Off

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
    SSLProtocol all -SSLv3 -TLSv1.2
    SSLHonorCipherOrder on

    # --- NEW: DirectoryIndex to allow accessing directory (optional) ---
    # DirectoryIndex index.php index.html # Uncomment if needed
    # --- END NEW ---

    <Files ~ "\.(cgi|shtml|phtml|php[3-8]?)$"> # Updated regex for PHP
        SSLOptions +StdEnvVars
    </Files>
    <Directory "/usr/local/apache2/cgi-bin">
        SSLOptions +StdEnvVars
    </Directory>
    # --- NEW: Add PHP handler for .php files ---
    <FilesMatch \.php$>
        SetHandler application/x-httpd-php
    </FilesMatch>
    # --- END NEW ---

    BrowserMatch "MSIE [2-5]" nokeepalive ssl-unclean-shutdown downgrade-1.0 force-response-1.0

    CustomLog "$APACHE_LOG_DIR/ssl_request_log" "%t %h %{SSL_PROTOCOL}x %{SSL_CIPHER}x \"%r\" %b"
</VirtualHost>
EOF

# Ensure the SSL config is included in the main configuration.
SSL_INCLUDE_LINE="Include conf/extra/httpd-ssl.conf"
if ! grep -qF "$SSL_INCLUDE_LINE" "$HTTPD_CONF"; then
    echo "${SSL_INCLUDE_LINE}" | sudo tee -a "$HTTPD_CONF" > /dev/null
fi

# Set ServerName explicitly
if ! grep -q "^ServerName" "$HTTPD_CONF"; then
    echo "ServerName localhost" | sudo tee -a "$HTTPD_CONF" > /dev/null
fi

# Set PID file location explicitly
if ! grep -q "^PidFile" "$HTTPD_CONF"; then
    echo "PidFile ${APACHE_LOG_DIR}/httpd.pid" | sudo tee -a "$HTTPD_CONF" > /dev/null
fi

# Test Apache configuration.
echo "[07_configure_apache] Testing Apache configuration..."
if sudo env LD_LIBRARY_PATH="$OPENSSL_PREFIX/lib" "$APACHE_PREFIX/bin/apachectl" configtest; then
    echo "[07_configure_apache] Apache config test successful."
else
    echo "[!] Apache config test failed. Please check logs and config files."
    # Optionally exit here if config test failure should stop the build
    # exit 1
fi

echo "[07_configure_apache] Apache configuration updated for PHP line-by-line serving."