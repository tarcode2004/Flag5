#!/bin/bash
set -euo pipefail
# Configuration variables
OPENSSL_VERSION="1.0.2u"
APACHE_VERSION="2.4.63"
APR_VERSION="1.7.5"
APR_UTIL_VERSION="1.6.3"
SRC_DIR=~/apache-openssl-build-src

echo "[02_download_sources] Creating source directory and downloading sources..."
mkdir -p "$SRC_DIR"
cd "$SRC_DIR"
wget -N "https://www.openssl.org/source/old/1.0.2/openssl-$OPENSSL_VERSION.tar.gz"
wget -N "https://downloads.apache.org/httpd/httpd-$APACHE_VERSION.tar.gz"
wget -N "https://downloads.apache.org/apr/apr-$APR_VERSION.tar.gz"
wget -N "https://downloads.apache.org/apr/apr-util-$APR_UTIL_VERSION.tar.gz"
