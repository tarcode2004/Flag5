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
RC4_KEY = b'CTF_KEY_12345'

class RC4LineHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/':
            self.send_error(404, "Not Found")
            return

        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()

        # Read all lines from the data file
        try:
            with open(TEXT_FILE, 'r') as f:
                lines = f.readlines()
        except FileNotFoundError:
            self.wfile.write(b'Error: data.txt not found\n')
            return

        if not lines:
            self.wfile.write(b'Error: data.txt is empty\n')
            return

        # Read the current line index
        try:
            with open(INDEX_FILE, 'r') as f:
                current_line = int(f.read().strip())
        except (FileNotFoundError, ValueError):
            current_line = 0

        # Ensure the index is within bounds
        current_line = current_line % len(lines)
        line = lines[current_line].strip()

        # Encrypt the line using RC4
        cipher = ARC4.new(RC4_KEY)
        encrypted_line = cipher.encrypt(line.encode())

        # Send the Base64-encoded encrypted line
        self.wfile.write(base64.b64encode(encrypted_line) + b'\n')

        # Update the line index
        try:
            with open(INDEX_FILE, 'w') as f:
                f.write(str((current_line + 1) % len(lines)))
        except IOError:
            self.wfile.write(b'Error: Unable to update line index\n')

def main():
    # Create SSL context
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=CERTFILE, keyfile=KEYFILE)

    # Create and start the HTTPS server
    server = http.server.HTTPServer((HOST, PORT), RC4LineHandler)
    server.socket = context.wrap_socket(server.socket, server_side=True)

    print(f"Serving on https://{HOST}:{PORT}")
    server.serve_forever()

if __name__ == '__main__':
    main()
