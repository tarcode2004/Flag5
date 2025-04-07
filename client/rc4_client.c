#include <openssl/ssl.h>
#include <openssl/err.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

int main() {
    SSL_CTX *ctx = NULL;
    SSL *ssl = NULL;
    int server_sock = -1;
    // Server IP address - change this as needed
    const char *server_ip = "127.0.0.1"; 
    // ... (Error handling omitted for brevity)

    // 1. Initialize OpenSSL
    SSL_library_init();
    OpenSSL_add_all_algorithms();
    SSL_load_error_strings();

    // 2. Create SSL Context (using a method compatible with TLSv1.0/1.1/1.2)
    ctx = SSL_CTX_new(SSLv23_client_method()); // Use SSLv23 for OpenSSL 1.0.2 compatibility

    // --- CRUCIAL PART ---
    // 3. Set Cipher List to ONLY RC4-SHA
    if (SSL_CTX_set_cipher_list(ctx, "RC4-SHA") != 1) {
        fprintf(stderr, "Error setting cipher string\n");
        ERR_print_errors_fp(stderr);
        // Handle error...
        goto cleanup;
    }
    // --- END CRUCIAL PART ---

    // 4. (Optional but recommended for testing) Disable certificate verification
    // WARNING: Insecure for production. Only for local testing with self-signed/CA cert.
    SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);

    // Main loop to make requests every 1 second
    while(1) {
        SSL *ssl = NULL;
        int server_sock = -1;
        
        // 5. Create TCP Socket and Connect
        server_sock = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in server_addr;
        memset(&server_addr, 0, sizeof(server_addr));
        server_addr.sin_family = AF_INET;
        server_addr.sin_port = htons(443);
        inet_pton(AF_INET, server_ip, &server_addr.sin_addr); // Use configured server IP

        if (connect(server_sock, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
             perror("TCP Connect failed");
             // Close resources and continue to next iteration
             if (server_sock >= 0) close(server_sock);
             sleep(1);
             continue;
        }
        printf("TCP connected.\n");

        // 6. Create SSL structure and associate with socket
        ssl = SSL_new(ctx);
        SSL_set_fd(ssl, server_sock);

        // 7. Perform SSL Handshake
        if (SSL_connect(ssl) != 1) {
            fprintf(stderr, "SSL Handshake failed\n");
            ERR_print_errors_fp(stderr);
            // Clean up this connection and continue
            if (ssl) SSL_free(ssl);
            if (server_sock >= 0) close(server_sock);
            sleep(1);
            continue;
        }
        printf("SSL Handshake successful. Cipher: %s\n", SSL_get_cipher(ssl));

        // 8. Send HTTP GET Request
        const char *http_request = "GET /satellite_uplink_status.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n";
        SSL_write(ssl, http_request, strlen(http_request));
        printf("HTTP Request sent.\n");

        // 9. Read HTTP Response
        char buffer[4096];
        int bytes_read;
        printf("--- Response ---\n");
        while ((bytes_read = SSL_read(ssl, buffer, sizeof(buffer) - 1)) > 0) {
            buffer[bytes_read] = 0;
            printf("%s", buffer);
        }
        printf("\n--- End Response ---\n");

        // Clean up for this iteration
        if (ssl) SSL_free(ssl);
        if (server_sock >= 0) close(server_sock);
        
        // Wait for 1 second before next request
        printf("Waiting 1 second for next request...\n");
        sleep(1);
    }

cleanup:
    // 10. Cleanup
    if (ctx) SSL_CTX_free(ctx);
    ERR_free_strings();
    EVP_cleanup(); // Clean up algorithms

    return 0;
}