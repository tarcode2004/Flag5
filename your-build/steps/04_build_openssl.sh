#!/bin/bash
set -euo pipefail
OPENSSL_VERSION="1.0.2u"
INSTALL_PREFIX="/usr/local"
OPENSSL_PREFIX="$INSTALL_PREFIX/ssl"
SRC_DIR=~/apache-openssl-build-src

echo "[04_build_openssl] Building OpenSSL $OPENSSL_VERSION..."
cd "$SRC_DIR/openssl-$OPENSSL_VERSION"
./config --prefix="$OPENSSL_PREFIX" --openssldir="$OPENSSL_PREFIX" shared
make clean
make -j$(nproc)
sudo make install_sw
sudo ldconfig
