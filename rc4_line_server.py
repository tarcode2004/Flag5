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
# --- Application-level RC4 key remains the same ---
RC4_KEY = b'CTF_KEY_12345' # Key for payload encryption

class RC4LineHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/':
            self.send_error(404, "Not Found")
            return

        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        # Optional: Remove or change the RC4 payload warning if desired
        # self.send_header('Warning', '299 - "Using insecure RC4 cipher for payload"')
        self.end_headers()

        # Read all lines from the data file
        try:
            with open(TEXT_FILE, 'r') as f:
                lines = f.readlines()
        except FileNotFoundError:
            self.wfile.write(b'Error: data.txt not found\n')
            print(f"Error: {TEXT_FILE} not found")
            return
        except Exception as e:
            self.wfile.write(b'Error: Cannot read data.txt\n')
            print(f"Error reading {TEXT_FILE}: {e}")
            return

        if not lines:
            self.wfile.write(b'Error: data.txt is empty\n')
            print(f"Error: {TEXT_FILE} is empty")
            return

        # Read the current line index (logic remains the same)
        current_line = 0
        try:
            with open(INDEX_FILE, 'r') as f:
                content = f.read().strip()
                if content:
                    current_line = int(content)
        except FileNotFoundError:
            print(f"Warning: {INDEX_FILE} not found, starting index at 0.")
            try:
                with open(INDEX_FILE, 'w') as f: f.write('0')
            except IOError as e: print(f"Error: Unable to create index file {INDEX_FILE}: {e}")
        except ValueError:
            print(f"Warning: Invalid content in {INDEX_FILE}, resetting index to 0.")
            current_line = 0
        except Exception as e:
             print(f"Error reading {INDEX_FILE}: {e}, using index 0.")
             current_line = 0

        # Ensure the index is within bounds
        current_line = current_line % len(lines)
        line = lines[current_line].strip()

        # --- Application-level RC4 encryption remains the same ---
        try:
            cipher = ARC4.new(RC4_KEY)
            encrypted_line = cipher.encrypt(line.encode('utf-8'))
        except Exception as e:
            self.wfile.write(b'Error: Encryption failed\n')
            print(f"Error encrypting line {current_line}: {e}")
            return

        # Send the Base64-encoded encrypted line
        try:
            self.wfile.write(base64.b64encode(encrypted_line) + b'\n')
        except Exception as e:
             print(f"Error sending response to client: {e}")

        # Update the line index (logic remains the same)
        next_line = (current_line + 1) % len(lines)
        try:
            with open(INDEX_FILE, 'w') as f:
                f.write(str(next_line))
        except IOError as e:
            print(f'Error: Unable to update line index file {INDEX_FILE}: {e}\n')


def main():
    print("Initializing Standard TLS Line Server...")
    # --- MODIFICATION NEEDED ---
    # Use standard TLS context (allows negotiation, typically TLS 1.2 or 1.3)
    # Python's default settings with a modern OpenSSL backend will support key logging.
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)

    # --- REMOVED: Do not force insecure RC4 TLS ciphers ---
    # try:
    #     print("Setting TLS cipher suite to enable RC4 (RC4-SHA:RC4-MD5)...")
    #     context.set_ciphers('RC4-SHA:RC4-MD5') # REMOVED THIS LINE
    #     print("Cipher suite set successfully.")
    # except ssl.SSLError as e:
    #     print(f"FATAL: Could not set RC4 cipher suite: {e}")
    #     exit(1)
    print("Using default TLS cipher suites (key logging compatible).")

    # Optionally set minimum TLS version if needed (e.g., require TLS 1.2+)
    # context.minimum_version = ssl.TLSVersion.TLSv1_2
    # print("Set minimum TLS version to 1.2")

    # Load the certificate and private key (remains the same)
    try:
        print(f"Loading certificate: {CERTFILE}")
        print(f"Loading private key: {KEYFILE}")
        context.load_cert_chain(certfile=CERTFILE, keyfile=KEYFILE)
        print("Certificate and key loaded.")
    except FileNotFoundError:
        print(f"FATAL: Certificate or key file not found.")
        print(f"Checked locations: {CERTFILE}, {KEYFILE}")
        exit(1)
    except ssl.SSLError as e:
        print(f"FATAL: Error loading certificate/key: {e}")
        exit(1)
    # --- END MODIFICATION ---

    # Create and start the HTTPS server (remains the same)
    try:
        server = http.server.HTTPServer((HOST, PORT), RC4LineHandler)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    except Exception as e:
        print(f"FATAL: Could not create or wrap HTTPS server socket: {e}")
        exit(1)

    print(f"Serving on https://{HOST}:{PORT} with standard TLS.")
    print("Application payload is still RC4 encrypted.")
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