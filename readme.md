# 🛰️ OmniTech Satellite Infiltration: RC4 Exploit Challenge

## 🌌 Mission Briefing

**CLASSIFIED: EYES ONLY**

The aging OmniTech-7 military satellite deployed in 2014 remains operational despite its outdated security protocols. Intelligence suggests this satellite is transmitting classified data using deprecated cryptographic standards. Your mission is to exploit its weak TLS implementation and intercept the classified communications.

Our reconnaissance has revealed:
* The satellite uses an obsolete ground control server running OpenSSL 1.0.2u
* All communications are "secured" with the vulnerable RC4 cipher
* System administrators never implemented brute-force protection for the admin portal
* A high-value intelligence payload (the flag) is hidden within the system

## 🔍 Technical Intelligence Report

The OmniTech-7 ground control server specifications:
* 📦 OpenSSL 1.0.2u (critically outdated)
* 🌐 Apache 2.4.63 compiled against the legacy OpenSSL version
* 🔒 HTTPS-only communications enforcing the insecure RC4-SHA cipher
* 💡 Intelligence suggests admin credentials have zero brute-force protection

This CTF challenge simulates the satellite's ground control server. Your objective: exploit the RC4 weaknesses to capture the flag.

---

## 🛠️ Server Deployment Instructions

Deploy the simulated satellite ground control server:

1. Clone this repository
2. Execute the deployment protocol:
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
