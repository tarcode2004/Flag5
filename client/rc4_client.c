#include <openssl/ssl.h>
#include <openssl/err.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <stdlib.h> // Needed for getenv if you were using it

--- REMOVED: Custom keylog callback is no longer needed ---
void ssl_keylog_callback(const SSL *ssl, const char *line) {
    // Define the file path directly here or get it from an env var if preferred
    const char *log_file_path = "/home/omnitech-admin/Desktop/sslkeylog.log";
    FILE *fp = fopen(log_file_path, "a"); // Open in append mode
    if (fp != NULL) {
        fprintf(fp, "%s\n", line);
        fclose(fp);
    } else {
        perror("Failed to open keylog file");
    }
}

int main() {
    SSL_CTX *ctx = NULL;
    SSL *ssl = NULL;
    int server_sock = -1;
    // --- Ensure this IP matches your server ---
    const char *server_ip = "192.168.56.101";

    SSL_library_init();
    OpenSSL_add_all_algorithms();
    SSL_load_error_strings();

    // Use a method compatible with key logging (TLS 1.2 is good)
    ctx = SSL_CTX_new(TLSv1_2_client_method());
    if (!ctx) {
        fprintf(stderr, "Error creating SSL_CTX\n");
        ERR_print_errors_fp(stderr);
        goto cleanup;
    }


    // --- REMOVED: Do not force insecure RC4 ciphers ---
    // if (SSL_CTX_set_cipher_list(ctx, "RC4-SHA:RC4-MD5") != 1) {
    //     fprintf(stderr, "Error setting cipher string\n");
    //     ERR_print_errors_fp(stderr);
    //     goto cleanup;
    // }
    printf("Using default TLS cipher list (key logging compatible).\n");

    // Keep restricting protocol to TLS 1.2 only if desired
    SSL_CTX_set_options(ctx, SSL_OP_NO_SSLv3 | SSL_OP_NO_TLSv1 | SSL_OP_NO_TLSv1_1);

    // Still disable server verification for self-signed certs
    SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);

    SSL_CTX_set_keylog_callback(ctx, ssl_keylog_callback);

    // --- REMOVED: Rely on SSLKEYLOGFILE environment variable instead ---
    // SSL_CTX_set_keylog_callback(ctx, ssl_keylog_callback);
    // Check if the environment variable is set (optional debug)
    if (getenv("SSLKEYLOGFILE")) {
         printf("SSLKEYLOGFILE environment variable is set to: %s\n", getenv("SSLKEYLOGFILE"));
    } else {
         printf("Warning: SSLKEYLOGFILE environment variable is not set. Key logging may not work.\n");
    }


    while(1) {
        // Create socket and SSL object inside the loop for reconnections
        server_sock = -1;
        ssl = NULL;

        server_sock = socket(AF_INET, SOCK_STREAM, 0);
        if (server_sock < 0) {
            perror("Socket creation failed");
            sleep(5); // Wait longer before retrying socket creation
            continue;
        }

        struct sockaddr_in server_addr;
        memset(&server_addr, 0, sizeof(server_addr));
        server_addr.sin_family = AF_INET;
        server_addr.sin_port = htons(443);
        if (inet_pton(AF_INET, server_ip, &server_addr.sin_addr) <= 0) {
            fprintf(stderr, "Invalid server IP address\n");
            close(server_sock);
            sleep(5);
            continue;
        }


        if (connect(server_sock, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
             perror("TCP Connect failed");
             close(server_sock);
             sleep(1); // Shorter sleep for connection retries
             continue;
        }

        ssl = SSL_new(ctx);
        if (!ssl) {
            fprintf(stderr, "Error creating SSL object\n");
            ERR_print_errors_fp(stderr);
            close(server_sock);
            sleep(1);
            continue;
        }
        SSL_set_fd(ssl, server_sock);

        // Set SNI (Server Name Indication) - good practice, though may not be strictly needed for IP connections
        // Use "localhost" or the CN from your server certificate if it differs
        SSL_set_tlsext_host_name(ssl, "localhost");


        if (SSL_connect(ssl) != 1) {
            fprintf(stderr, "SSL Handshake failed\n");
            ERR_print_errors_fp(stderr); // Print details on handshake failure
            SSL_free(ssl);
            close(server_sock);
            sleep(1);
            continue;
        }
        printf("SSL Handshake successful. Cipher: %s\n", SSL_get_cipher(ssl));

        const char *http_request = "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n";
        if (SSL_write(ssl, http_request, strlen(http_request)) <= 0) {
            fprintf(stderr, "SSL_write failed\n");
            ERR_print_errors_fp(stderr);
            SSL_free(ssl);
            close(server_sock);
            sleep(1);
            continue;
        }


        char buffer[4096];
        int bytes_read;
        printf("--- Server Response (Base64/RC4 Encoded) ---\n");
        while ((bytes_read = SSL_read(ssl, buffer, sizeof(buffer) - 1)) > 0) {
            buffer[bytes_read] = 0;
            printf("%s", buffer); // Print raw response chunk
        }
        // Check for read errors *after* the loop
        if (bytes_read < 0) {
             int ssl_err = SSL_get_error(ssl, bytes_read);
             fprintf(stderr, "SSL_read failed with error code: %d\n", ssl_err);
             ERR_print_errors_fp(stderr);
        }
        printf("\n--- End Response ---\n");


        SSL_shutdown(ssl); // Clean shutdown
        SSL_free(ssl);
        close(server_sock);

        sleep(1); // Wait before next request
    }

cleanup:
    // Note: In an infinite loop, cleanup might not be reached unless there's an error breaking out.
    // Consider signal handling for graceful shutdown if needed.
    if (ssl) SSL_free(ssl); // Should be freed in loop, but belt-and-suspenders
    if (server_sock >= 0) close(server_sock);
    if (ctx) SSL_CTX_free(ctx);
    ERR_free_strings();
    EVP_cleanup();

    return 0; // Or appropriate error code
}