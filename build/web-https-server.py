"""HTTPS-Testserver fuer den Web-Build - wird von test-web.bat aufgerufen.

Warum nicht einfach "python -m http.server": Godot verlangt im Browser einen
Secure Context. Als vertrauenswuerdig gelten nur https:// sowie localhost und
127.0.0.1 - eine nackte LAN-IP ueber HTTP faellt durch, und die Engine bricht
mit "Secure Context - Check web server configuration (use HTTPS)" ab, noch
bevor sie index.wasm laedt. Ueber HTTPS klappt es auch mit einem
selbstsignierten Zertifikat, sobald man am Geraet einmal durch die
Browser-Warnung getippt hat.

Aufruf: python web-https-server.py <port> <wurzelverzeichnis> <server.pem>
Das PEM enthaelt Zertifikat und Schluessel hintereinander.
"""

import http.server
import os
import ssl
import sys

if len(sys.argv) != 4:
    print(__doc__)
    sys.exit(2)

port = int(sys.argv[1])
root = sys.argv[2]
pem = sys.argv[3]

os.chdir(root)

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(pem)

httpd = http.server.ThreadingHTTPServer(
    ("0.0.0.0", port), http.server.SimpleHTTPRequestHandler
)
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

print("HTTPS-Server laeuft auf Port %d, Wurzel: %s" % (port, root), flush=True)
try:
    httpd.serve_forever()
except KeyboardInterrupt:
    print("\nBeendet.", flush=True)
