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

# --- REMOVED Global Cipher Initialization ---
# No shared cipher object needed if we reset for each message

class RC4LineHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # --- REMOVED global declaration ---

        if self.path != '/':
            self.send_error(404, "Not Found")
            return

        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()

        # Read data file (logic remains the same)
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

        # Read index file (logic remains the same)
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

        current_line = current_line % len(lines)
        line = lines[current_line].strip()

        # --- MODIFICATION: Re-initialize Cipher for EACH request ---
        try:
            # Create a NEW cipher instance here, resetting the state every time
            # This uses the same *starting* keystream segment for every message.
            # WARNING: This creates the "many-time pad" vulnerability.
            cipher = ARC4.new(RC4_KEY)
            encrypted_line = cipher.encrypt(line.encode('utf-8'))
            print(f"Encrypted line {current_line} using RESET RC4 state.") # Debug print
        except Exception as e:
            self.wfile.write(b'Error: Encryption failed\n')
            print(f"Error encrypting line {current_line}: {e}")
            return
        # --- END MODIFICATION ---

        # Send Base64 encoded data (logic remains the same)
        try:
            self.wfile.write(base64.b64encode(encrypted_line) + b'\n')
        except Exception as e:
             print(f"Error sending response to client: {e}")

        # Update index file (logic remains the same)
        next_line = (current_line + 1) % len(lines)
        try:
            with open(INDEX_FILE, 'w') as f:
                f.write(str(next_line))
        except IOError as e:
            print(f'Error: Unable to update line index file {INDEX_FILE}: {e}\n')


def main():
    # Standard TLS setup remains the same
    print("Initializing Standard TLS Line Server with RC4 Keystream RESET per message...")
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    print("Using default TLS cipher suites (key logging compatible).")

    # Load cert/key (logic remains the same)
    try:
        print(f"Loading certificate: {CERTFILE}")
        print(f"Loading private key: {KEYFILE}")
        context.load_cert_chain(certfile=CERTFILE, keyfile=KEYFILE)
        print("Certificate and key loaded.")
    except FileNotFoundError:
        print(f"FATAL: Certificate or key file not found.")
        exit(1)
    except ssl.SSLError as e:
        print(f"FATAL: Error loading certificate/key: {e}")
        exit(1)

    # Start server (logic remains the same)
    try:
        server = http.server.HTTPServer((HOST, PORT), RC4LineHandler)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    except Exception as e:
        print(f"FATAL: Could not create or wrap HTTPS server socket: {e}")
        exit(1)

    print(f"Serving on https://{HOST}:{PORT} with standard TLS.")
    print("WARNING: Application payload RC4 keystream is RESET and REUSED ('many-time pad')!")
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