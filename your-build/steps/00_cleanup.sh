#!/bin/bash
set -euo pipefail
echo "[00_cleanup] Stopping default Apache and removing conflicting packages..."
sudo systemctl stop apache2 || true
sudo systemctl disable apache2 || true
sudo apt-get purge -y apache2 apache2-utils libssl-dev || true
sudo apt-get autoremove -y || true
