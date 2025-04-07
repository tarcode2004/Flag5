# 🛰️ RC4 Apache CTF Challenge

This repository contains a Capture The Flag (CTF) challenge focusing on exploiting a deliberately vulnerable Apache server configured with deprecated cryptographic protocols. The setup creates a server using an old version of OpenSSL and configures Apache to use the vulnerable RC4 cipher.

---

## 🔍 Challenge Overview

The challenge simulates an "**OmniTech Satellite Uplink**" server that contains a secret flag. The server uses:

* 📦 OpenSSL 1.0.2u (an outdated version)
* 🌐 Apache 2.4.63 compiled against the old OpenSSL
* 🔒 HTTPS-only configuration with the insecure RC4-SHA cipher enforced
* 💡 A hint in the uplink status file suggesting admin credentials have no brute-force protection

---

## 🛠️ Server Setup

The repository includes an automated build process through a series of bash scripts:

1. Clone this repository
2. Run the build process:
bash
cd your-build
./main.sh


### Build Process Steps:

1. Stops any existing Apache server
2. Installs necessary build dependencies
3. Downloads OpenSSL 1.0.2u, Apache 2.4.63, and APR sources
4. Builds OpenSSL with custom configuration in `/usr/local/ssl`
5. Builds Apache with SSL support linking to the custom OpenSSL
6. Configures Apache to run HTTPS-only with RC4-SHA cipher
7. Creates a systemd service (`apache2-custom`) to run on startup
8. Places a file with encoded data at `/usr/local/apache2/htdocs/satellite_uplink_status.txt`

---

## 💻 Client Setup

A test client is provided in the `client` directory to verify the vulnerability:
bash
cd client
gcc rc4_client.c -o rc4_client \
-I/usr/local/ssl/include \
-L/usr/local/ssl/lib \
-lssl -lcrypto -ldl -pthread
export LD_LIBRARY_PATH=/usr/local/ssl/lib:$LD_LIBRARY_PATH
./rc4_client


The client will connect to the server using the vulnerable RC4-SHA cipher and retrieve the satellite uplink status file.

---

## 📁 Key Locations

| Component | Location |
|-----------|----------|
| **OpenSSL** | `/usr/local/ssl` |
| **Apache** | `/usr/local/apache2` |
| **Apache Config** | `/usr/local/apache2/conf/httpd.conf` |
| **SSL Config** | `/usr/local/apache2/conf/extra/httpd-ssl.conf` |
| **Website Content** | `/usr/local/apache2/htdocs` |
| **Log Files** | `/usr/local/apache2/logs` |
| **Systemd Service** | `/etc/systemd/system/apache2-custom.service` |

---

## 🚩 Exploitation Hints

To capture the flag in this challenge:

1. Analyze the RC4 cipher weakness - RC4 has known cryptographic vulnerabilities
2. Note that the uplink status file contains an encoded string:
   ```
   6f5b3e8c9d2a1f7e4b0c8d9e2f5a1b7c3d9e0f5a2b7c4d8e1f5a3b9c6d0e2f7
   ```
3. Observe the hint about "**admin lacks brute-force protection**"
4. Use tools like Wireshark to capture the SSL traffic and analyze the RC4 encryption

### The vulnerability may involve:

* RC4 biases in the keystream
* Potential for plaintext recovery with enough samples
* Weak authentication mechanisms
* Potential for brute-forcing admin credentials

---

## ✅ Verification

After setting up, you can verify the server is working correctly:

1. Check that Apache is running and only listening on port 443:
   ```bash
   sudo systemctl status apache2-custom
   sudo ss -tulnp | grep ':443'
   ```

2. Verify RC4-SHA is being used by running the test client:
   ```bash
   ./client/rc4_client
   ```

> The output should show "SSL Handshake successful. Cipher: RC4-SHA" and display the contents of the satellite uplink status file.

---

## 🎯 Happy hacking!
