#!/bin/bash
set -euo pipefail

echo "[11_disable_brute_force_protections] Disabling brute force protections for CTF..."

# 0. Ensure SSH server is installed and running
if ! dpkg -l | grep -q openssh-server; then
    echo "  - SSH server not found, installing openssh-server..."
    sudo apt-get update
    sudo apt-get install -y openssh-server
fi

# Check if SSH service is running, if not start it
if ! systemctl is-active --quiet ssh; then
    echo "  - Starting SSH service..."
    sudo systemctl enable ssh
    sudo systemctl start ssh
fi

# 1. Disable fail2ban if installed
if command -v fail2ban-client &> /dev/null; then
    echo "  - Stopping and disabling fail2ban service"
    sudo systemctl stop fail2ban
    sudo systemctl disable fail2ban
    sudo systemctl mask fail2ban
fi

# 2. Configure SSH to allow unlimited attempts
SSHD_CONFIG="/etc/ssh/sshd_config"
echo "  - Configuring SSH to allow unlimited login attempts"

# Remove any MaxAuthTries, LoginGraceTime, MaxStartups limitations
sudo sed -i '/^MaxAuthTries/d' $SSHD_CONFIG
sudo sed -i '/^LoginGraceTime/d' $SSHD_CONFIG
sudo sed -i '/^MaxStartups/d' $SSHD_CONFIG

# Add our permissive settings
echo "# CTF Challenge Settings - INSECURE" | sudo tee -a $SSHD_CONFIG
echo "MaxAuthTries 100" | sudo tee -a $SSHD_CONFIG
echo "LoginGraceTime 120" | sudo tee -a $SSHD_CONFIG
echo "MaxStartups 100:30:200" | sudo tee -a $SSHD_CONFIG
echo "PermitRootLogin yes" | sudo tee -a $SSHD_CONFIG

# 3. Disable PAM account lockout mechanisms
echo "  - Disabling PAM account lockout mechanisms"

# Check for pam_tally2 (older Ubuntu)
if grep -q "pam_tally2" /etc/pam.d/common-auth; then
    sudo sed -i '/pam_tally2.so/d' /etc/pam.d/common-auth
    sudo sed -i '/pam_tally2.so/d' /etc/pam.d/common-account
fi

# Check for pam_faillock (newer Ubuntu)
if grep -q "pam_faillock" /etc/pam.d/common-auth; then
    sudo sed -i '/pam_faillock.so/d' /etc/pam.d/common-auth
    sudo sed -i '/pam_faillock.so/d' /etc/pam.d/common-account
fi

# Clear any existing account lockouts
if command -v pam_tally2 &> /dev/null; then
    sudo pam_tally2 --reset --user root || true
    sudo pam_tally2 --reset --user admin || true
    sudo pam_tally2 --reset --user ubuntu || true
elif command -v faillock &> /dev/null; then
    sudo faillock --reset --user root || true
    sudo faillock --reset --user admin || true
    sudo faillock --reset --user ubuntu || true
fi

# 4. Make sure user "admin" exists with a simple password
if ! id -u admin &>/dev/null; then
    echo "  - Creating admin user for brute force attempts"
    sudo useradd -m -s /bin/bash admin
    echo "admin:space2025" | sudo chpasswd
fi

# 5. Disable any rate-limiting iptables rules
echo "  - Removing any SSH rate-limiting firewall rules"
# Remove any REJECT rules targeting SSH port
sudo iptables -L INPUT --line-numbers | grep "REJECT.*dpt:ssh" | \
  awk '{print $1}' | sort -r | xargs -I {} sudo iptables -D INPUT {} || true

# 6. Set SSHD to accept password auth (no keys required)
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' $SSHD_CONFIG || true
sudo sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' $SSHD_CONFIG || true

# 7. Create a banner warning about the insecure setup
echo "WARNING: This system has been configured to allow brute force attacks for CTF purposes. DO NOT use in production." | \
  sudo tee /etc/ssh/banner || true
echo "Banner /etc/ssh/banner" | sudo tee -a $SSHD_CONFIG || true

# 8. Restart SSH to apply changes
echo "  - Restarting SSH service to apply changes"
sudo systemctl restart ssh || true

echo "[11_disable_brute_force_protections] Brute force protections successfully disabled!"
echo "The system is now vulnerable to brute force attacks through SSH."
echo "Players can use tools like Hydra to crack the admin password." 