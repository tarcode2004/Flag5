#!/bin/bash
set -euo pipefail
APACHE_VERSION="2.4.63"
SRC_DIR=~/apache-openssl-build-src
echo "[05_prepare_apache_source] Preparing Apache source tree with APR and APR-Util..."
cd "$SRC_DIR/httpd-$APACHE_VERSION"
rm -rf srclib/apr srclib/apr-util
cp -R "$SRC_DIR/apr-1.7.5" ./srclib/apr
cp -R "$SRC_DIR/apr-util-1.6.3" ./srclib/apr-util
