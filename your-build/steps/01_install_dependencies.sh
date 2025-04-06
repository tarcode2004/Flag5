#!/bin/bash
set -euo pipefail
echo "[01_install_dependencies] Updating package lists and installing build dependencies..."
sudo apt-get update
sudo apt-get install -y build-essential libpcre3-dev zlib1g-dev libtool wget curl make libexpat1-dev
