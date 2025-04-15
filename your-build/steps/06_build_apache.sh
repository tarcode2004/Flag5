#!/bin/bash
set -euo pipefail
OPENSSL_PREFIX="/usr/local/ssl"
APACHE_VERSION="2.4.63"
INSTALL_PREFIX="/usr/local"
APACHE_PREFIX="$INSTALL_PREFIX/apache2"
SRC_DIR=~/apache-openssl-build-src

echo "[06_build_apache] Configuring and building Apache $APACHE_VERSION..."
cd "$SRC_DIR/httpd-$APACHE_VERSION"
export CPPFLAGS="-I$OPENSSL_PREFIX/include"
export LDFLAGS="-L$OPENSSL_PREFIX/lib -Wl,-rpath=$OPENSSL_PREFIX/lib"
export LD_LIBRARY_PATH="$OPENSSL_PREFIX/lib"

./configure \
  --prefix="$APACHE_PREFIX" \
  --enable-ssl \
  --with-ssl="$OPENSSL_PREFIX" \
  --enable-so \
  --with-included-apr \
  --with-mpm=prefork \
  --enable-mods-shared=reallyall

make clean
make -j$(nproc)
sudo make install

# Verify that mod_ssl is linked against our custom OpenSSL.
INSTALLED_MOD_SSL="$APACHE_PREFIX/modules/mod_ssl.so"
if [ ! -f "$INSTALLED_MOD_SSL" ]; then
    echo "[!] mod_ssl.so not found. Exiting."
    exit 1
fi
ldd "$INSTALLED_MOD_SSL" | grep "$OPENSSL_PREFIX/lib/libssl" || { echo "[!] mod_ssl not linked with custom libssl. Exiting."; exit 1; }

unset CPPFLAGS LDFLAGS LD_LIBRARY_PATH
