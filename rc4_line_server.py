#!/usr/bin/env python3
import http.server
import ssl
import socket
from Crypto.Cipher import ARC4
import os
import base64

# Configuration
HOST = '0.0.0.0'
PORT = 443
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CERTFILE = os.path.join(SCRIPT_DIR, 'certs', 'server.crt')
KEYFILE = os.path.join(SCRIPT_DIR, 'certs', 'server.key')
TEXT_FILE = os.path.join(SCRIPT_DIR, 'data.txt')

class RC4LineHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            
            # Read the file and get current line
            with open(TEXT_FILE, 'r') as f:
                lines = f.readlines()
            
            # Get current line index from file
            try:
                with open('line_index.txt', 'r') as f:
                    current_line = int(f.read().strip())
            except (FileNotFoundError, ValueError):
                current_line = 0
            
            # Get the line to serve
            line = lines[current_line % len(lines)].strip()
            
            # Encrypt the line with RC4
            # Using a fixed key for demonstration - in real CTF this would be the vulnerability
            key = b'CTF_KEY_12345'
            cipher = ARC4.new(key)
            encrypted = cipher.encrypt(line.encode())
            
            # Send the encrypted line
            self.wfile.write(base64.b64encode(encrypted) + b'\n')
            
            # Update line index
            with open('line_index.txt', 'w') as f:
                f.write(str((current_line + 1) % len(lines)))

def main():
    # Create SSL context
    context = ssl.SSLContext(ssl.PROTOCOL_TLSv1_2)
    # Explicitly allow RC4 ciphers
    context.set_ciphers('RC4-SHA:RC4-MD5:@SECLEVEL=1')
    context.load_cert_chain(certfile=CERTFILE, keyfile=KEYFILE)
    
    # Create server
    server = http.server.HTTPServer((HOST, PORT), RC4LineHandler)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    
    print(f"Serving on https://{HOST}:{PORT}")
    server.serve_forever()

if __name__ == '__main__':
    main() 