gcc rc4_client.c -o rc4_client \
    -I/usr/local/ssl/include \
    -L/usr/local/ssl/lib \
    -lssl -lcrypto -ldl -pthread

export LD_LIBRARY_PATH=/usr/local/ssl/lib:$LD_LIBRARY_PATH
./rc4_client # or ./rc4_curl_client