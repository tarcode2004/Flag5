# Compile Server Binary
```bash
gcc rc4_client.c -o rc4_client \
    -I/usr/local/ssl/include \
    -L/usr/local/ssl/lib \
    -lssl -lcrypto -ldl -pthread
```

# Run Binary
```bash
export LD_LIBRARY_PATH=/usr/local/ssl/lib:$LD_LIBRARY_PATH
./rc4_client
```

# Setup Automatic Startup
To configure the client to automatically start when the VM boots:

1. First compile the binary using the instructions above
2. Make the setup script executable:
```bash
chmod +x setup_autostart.sh
```
3. Run the setup script with sudo:
```bash
sudo ./setup_autostart.sh
```
This script creates a systemd service that will:
- Start the RC4 client automatically when the VM boots
- Restart the client if it crashes
- Set the proper library path required by the client

To check if the service is running:
```bash
systemctl status rc4-client.service
```
To stop the automatic startup:
```bash
sudo systemctl disable rc4-client.service
sudo systemctl stop rc4-client.service
```
