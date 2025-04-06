#!/bin/bash
set -euo pipefail
SRC_DIR=~/apache-openssl-build-src
cd "$SRC_DIR"
echo "[03_extract_sources] Extracting downloaded sources if not already extracted..."
if [ ! -d "openssl-1.0.2u" ]; then
    tar xzf "openssl-1.0.2u.tar.gz"
fi
if [ ! -d "httpd-2.4.63" ]; then
    tar xzf "httpd-2.4.63.tar.gz"
fi
if [ ! -d "apr-1.7.5" ]; then
    tar xzf "apr-1.7.5.tar.gz"
fi
if [ ! -d "apr-util-1.6.3" ]; then
    tar xzf "apr-util-1.6.3.tar.gz"
fi
