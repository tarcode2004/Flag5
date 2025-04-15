#!/usr/bin/env python3
import http.server
import ssl
import os
import base64
from Crypto.Cipher import ARC4

# Configuration
HOST = '0.0.0.0'
PORT = 443
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CERTFILE = os.path.join(SCRIPT_DIR, 'certs', 'server.crt')
KEYFILE = os.path.join(SCRIPT_DIR, 'certs', 'server.key')
TEXT_FILE = os.path.join(SCRIPT_DIR, 'data.txt')
INDEX_FILE = os.path.join(SCRIPT_DIR, 'line_index.txt')
RC4_KEY = b'CTF_KEY_12345' # Key for payload encryption

class RC4LineHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/':
            self.send_error(404, "Not Found")
            return

        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        # Add a header to indicate the weak cipher usage (optional but good practice)
        self.send_header('Warning', '299 - "Using insecure RC4 cipher for payload"')
        self.end_headers()

        # Read all lines from the data file
        try:
            with open(TEXT_FILE, 'r') as f:
                lines = f.readlines()
        except FileNotFoundError:
            self.wfile.write(b'Error: data.txt not found\n')
            print(f"Error: {TEXT_FILE} not found") # Added server-side logging
            return
        except Exception as e:
            self.wfile.write(b'Error: Cannot read data.txt\n')
            print(f"Error reading {TEXT_FILE}: {e}") # Added server-side logging
            return


        if not lines:
            self.wfile.write(b'Error: data.txt is empty\n')
            print(f"Error: {TEXT_FILE} is empty") # Added server-side logging
            return

        # Read the current line index
        current_line = 0 # Default to 0
        try:
            with open(INDEX_FILE, 'r') as f:
                content = f.read().strip()
                if content: # Ensure file is not empty
                    current_line = int(content)
        except FileNotFoundError:
            print(f"Warning: {INDEX_FILE} not found, starting index at 0.")
            # Create the file if it doesn't exist
            try:
                with open(INDEX_FILE, 'w') as f:
                    f.write('0')
            except IOError as e:
                 print(f"Error: Unable to create index file {INDEX_FILE}: {e}")
                 # Decide if this is fatal or not, here we continue with index 0
        except ValueError:
            print(f"Warning: Invalid content in {INDEX_FILE}, resetting index to 0.")
            current_line = 0
        except Exception as e:
             print(f"Error reading {INDEX_FILE}: {e}, using index 0.")
             current_line = 0


        # Ensure the index is within bounds
        current_line = current_line % len(lines)
        line = lines[current_line].strip()

        # Encrypt the line using RC4 (Payload Encryption)
        try:
            cipher = ARC4.new(RC4_KEY)
            encrypted_line = cipher.encrypt(line.encode('utf-8')) # Specify encoding
        except Exception as e:
            self.wfile.write(b'Error: Encryption failed\n')
            print(f"Error encrypting line {current_line}: {e}")
            return

        # Send the Base64-encoded encrypted line
        try:
            self.wfile.write(base64.b64encode(encrypted_line) + b'\n')
        except Exception as e:
             print(f"Error sending response to client: {e}")
             # Connection might be broken, nothing else to do here

        # Update the line index
        next_line = (current_line + 1) % len(lines)
        try:
            with open(INDEX_FILE, 'w') as f:
                f.write(str(next_line))
        except IOError as e:
            # Log error, but don't send error to client as response is already sent
            print(f'Error: Unable to update line index file {INDEX_FILE}: {e}\n')


def main():
    print("Initializing RC4 Line Server...")
    # --- MODIFICATION NEEDED ---
    # Create SSL context - Use TLS 1.2 as max, compatible with OpenSSL 1.0.2
    # PROTOCOL_TLS_SERVER allows negotiation, should work fine with 1.0.2 -> TLS 1.2
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)

    # Explicitly set allowed cipher suites to match the C client requirement
    # Your C client uses "RC4-SHA:RC4-MD5:@SECLEVEL=1"
    # We need to enable RC4 on the server for the TLS handshake itself.
    # WARNING: RC4 is insecure and broken. Use only if absolutely required.
    try:
        print("Setting TLS cipher suite to enable RC4 (RC4-SHA:RC4-MD5)...")
        context.set_ciphers('RC4-SHA:RC4-MD5')
        print("Cipher suite set successfully.")
    except ssl.SSLError as e:
        print(f"FATAL: Could not set RC4 cipher suite: {e}")
        print("Ensure the custom Python build linked correctly against OpenSSL 1.0.2u.")
        print("Modern OpenSSL versions might prevent setting RC4.")
        exit(1)

    # Optionally, be explicit about protocol versions (though negotiation should handle it)
    # In Python 3.9, setting minimum_version might not work as cleanly as options
    # context.options |= ssl.OP_NO_SSLv3 | ssl.OP_NO_TLSv1 | ssl.OP_NO_TLSv1_1
    # print("Disabled SSLv3, TLSv1.0, TLSv1.1.")

    # Load the certificate and private key
    try:
        print(f"Loading certificate: {CERTFILE}")
        print(f"Loading private key: {KEYFILE}")
        context.load_cert_chain(certfile=CERTFILE, keyfile=KEYFILE)
        print("Certificate and key loaded.")
    except FileNotFoundError:
        print(f"FATAL: Certificate or key file not found.")
        print(f"Checked locations: {CERTFILE}, {KEYFILE}")
        print("Ensure certificates are generated by the setup script.")
        exit(1)
    except ssl.SSLError as e:
        print(f"FATAL: Error loading certificate/key: {e}")
        print("Ensure certificate and key files are valid and permissions are correct (key should be readable by root).")
        exit(1)
    # --- END MODIFICATION ---

    # Create and start the HTTPS server
    try:
        server = http.server.HTTPServer((HOST, PORT), RC4LineHandler)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    except Exception as e:
        print(f"FATAL: Could not create or wrap HTTPS server socket: {e}")
        print(f"Ensure port {PORT} is free and permissions are sufficient.")
        exit(1)

    print(f"Serving on https://{HOST}:{PORT} with RC4 TLS Ciphers ENABLED.")
    print("WARNING: This configuration is INSECURE.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped by user.")
    except Exception as e:
        print(f"Server error: {e}")
    finally:
        server.server_close()
        print("Server shut down.")


if __name__ == '__main__':
    main()