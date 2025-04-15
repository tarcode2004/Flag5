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
    const char *server_ip = "192.168.56.101"; 

    SSL_library_init();
    OpenSSL_add_all_algorithms();
    SSL_load_error_strings();

    ctx = SSL_CTX_new(TLSv1_2_client_method());

    if (SSL_CTX_set_cipher_list(ctx, "RC4-SHA:RC4-MD5") != 1) {
        fprintf(stderr, "Error setting cipher string\n");
        ERR_print_errors_fp(stderr);
        goto cleanup;
    }
    
    SSL_CTX_set_options(ctx, SSL_OP_NO_SSLv3 | SSL_OP_NO_TLSv1 | SSL_OP_NO_TLSv1_1);  // Only allow TLSv1.2

    SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);

    while(1) {
        SSL *ssl = NULL;
        int server_sock = -1;
        
        server_sock = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in server_addr;
        memset(&server_addr, 0, sizeof(server_addr));
        server_addr.sin_family = AF_INET;
        server_addr.sin_port = htons(443);
        inet_pton(AF_INET, server_ip, &server_addr.sin_addr); 

        if (connect(server_sock, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
             perror("TCP Connect failed");
             if (server_sock >= 0) close(server_sock);
             sleep(1);
             continue;
        }
        // printf("TCP connected.\n"); // Optional: Less verbose output

        ssl = SSL_new(ctx);
        SSL_set_fd(ssl, server_sock);

        if (SSL_connect(ssl) != 1) {
            fprintf(stderr, "SSL Handshake failed\n");
            // ERR_print_errors_fp(stderr); // Optional: Less verbose error
            if (ssl) SSL_free(ssl);
            if (server_sock >= 0) close(server_sock);
            sleep(1);
            continue;
        }
        // printf("SSL Handshake successful. Cipher: %s\n", SSL_get_cipher(ssl)); // Optional

        // --- MODIFIED: Request the PHP script ---
        const char *http_request = "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n";
        // --- END MODIFIED ---
        
        SSL_write(ssl, http_request, strlen(http_request));
        // printf("HTTP Request sent.\n"); // Optional

        // --- MODIFIED: Read HTTP Response (less verbose) ---
        char buffer[4096];
        int bytes_read;
        // printf("--- Response Line ---\n"); // Optional
        while ((bytes_read = SSL_read(ssl, buffer, sizeof(buffer) - 1)) > 0) {
            buffer[bytes_read] = 0;
            printf("%s", buffer); // Print raw response chunk
        }
        // printf("--- End Response Line ---\n"); // Optional
        // --- END MODIFIED ---

        if (ssl) SSL_free(ssl);
        if (server_sock >= 0) close(server_sock);
        
        // printf("Waiting 1 second...\n"); // Optional
        sleep(1);
    }

cleanup:
    if (ctx) SSL_CTX_free(ctx);
    ERR_free_strings();
    EVP_cleanup(); 

    return 0;
}