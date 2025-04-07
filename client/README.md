# RC4 Client

This client connects to a server using RC4-SHA encryption and requests satellite uplink status information.

## Quick Setup (Recommended)

To automatically compile, install dependencies, and configure the client to start on boot:

```bash
# Make the setup script executable
chmod +x setup_autostart.sh

# Run the setup script with sudo
sudo ./setup_autostart.sh
```

This script will:
- Install any required build dependencies
- Install OpenSSL if needed
- Compile the RC4 client 
- Create a systemd service that starts automatically when the VM boots
- Start the service immediately

## Manual Compilation (Only if modifying the code)

If you need to modify the client code (for example, to change the destination IP address in rc4_client.c), you can compile manually:

```bash
gcc rc4_client.c -o rc4_client \
    -I/usr/local/ssl/include \
    -L/usr/local/ssl/lib \
    -lssl -lcrypto -ldl -pthread
```

## Running Manually (For testing)

If you need to run the client manually:

```bash
export LD_LIBRARY_PATH=/usr/local/ssl/lib:$LD_LIBRARY_PATH
./rc4_client
```

## Managing the Service

To check if the service is running:
```bash
systemctl status rc4-client.service
```

To stop the automatic startup:
```bash
sudo systemctl disable rc4-client.service
sudo systemctl stop rc4-client.service
```

To restart the service after making changes:
```bash
sudo systemctl restart rc4-client.service
```
